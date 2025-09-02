defmodule LlmComposer do
  @moduledoc """
  `LlmComposer` is responsible for interacting with a language model to perform chat-related operations,
  such as running completions and executing functions based on the responses. The module provides
  functionality to handle user messages, generate responses, and automatically execute functions as needed.

  ## Example Usage

  To use `LlmComposer` for creating a simple chat interaction with a language model, define a settings configuration and initiate a chat:

  ```elixir
  # Define the settings for your LlmComposer instance
  settings = %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.OpenAI,  [model: "gpt-4o-mini"]}
    ],
    system_prompt: "You are a helpful assistant.",
    user_prompt_prefix: "",
    auto_exec_functions: false,
    functions: [],
    api_key: ""
  }

  # Initiate a simple chat interaction with the defined settings
  {:ok, response} = LlmComposer.simple_chat(settings, "Hello, how are you?")

  # Print the main response from the assistant
  IO.inspect(response.main_response)
  ```

  ### Output Example

  Running this code might produce the following log and output:

  ```
  16:41:07.594 [debug] input_tokens=18, output_tokens=9
  %LlmComposer.Message{
    type: :assistant,
    content: "Hello! How can I assist you today?"
  }
  ```

  In this example, the simple_chat/2 function sends the user's message to the language model using the provided settings, and the response is displayed as the assistant's reply.
  """

  alias LlmComposer.Helpers
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message
  alias LlmComposer.Settings

  require Logger

  @deprecated_msg """
  The settings keys :provider and :provider_opts are deprecated and will be removed in version 0.10.0.
  Please migrate your configuration to use the :providers list instead.
  """

  @type messages :: [Message.t()]

  @doc """
  Initiates a simple chat interaction with the language model.

  ## Parameters
    - `settings`: The settings for the language model, including prompts and options.
    - `msg`: The user message to be sent to the language model.

  ## Returns
    - The result of the language model's response, which may include function executions if specified.
  """
  @spec simple_chat(Settings.t(), String.t()) :: Helpers.action_result()
  def simple_chat(%Settings{} = settings, msg) do
    validate_settings(settings)

    messages = [Message.new(:user, user_prompt(settings, msg, %{}))]

    run_completion(settings, messages)
  end

  @doc """
  Runs the completion process by sending messages to the language model and handling the response.

  ## Parameters
    - `settings`: The settings for the language model, including prompts, model options, and functions.
    - `messages`: The list of messages to be sent to the language model.
    - `previous_response` (optional): The previous response object, if any, used for context.

  ## Returns
    - A tuple containing `:ok` with the response or `:error` if the model call fails.
  """
  @spec run_completion(Settings.t(), messages(), LlmResponse.t() | nil) ::
          Helpers.action_result()
  def run_completion(settings, messages, previous_response \\ nil) do
    validate_settings(settings)

    system_msg = Message.new(:system, settings.system_prompt)

    messages
    |> fallback_run(settings, system_msg)
    |> then(fn
      {:ok, res} ->
        # set previous response all the time
        res = %LlmResponse{res | previous_response: previous_response}

        Logger.debug("input_tokens=#{res.input_tokens}, output_tokens=#{res.output_tokens}")

        if settings.auto_exec_functions do
          maybe_run_functions(res, messages, settings)
        else
          {:ok, res}
        end

      {:error, _data} = resp ->
        resp
    end)
  end

  @doc """
  Processes a raw stream response and returns a parsed stream of message content.

  ## Parameters
    - `stream`: The raw stream object from the LLM response.

  ## Returns
    - A stream that yields parsed content strings, filtering out "[DONE]" markers and decode errors.

  ## Example

    ```elixir
    # Stream tested with Finch, maybe works with other adapters.
    Application.put_env(:llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyFinch})
    {:ok, finch} = Finch.start_link(name: MyFinch)

    settings = %LlmComposer.Settings{
      provider: LlmComposer.Providers.Ollama,
      provider_opts: [model: "llama3.2"],
      stream_response: true
    }
    
    messages = [
      %LlmComposer.Message{type: :user, content: "Tell me a short story"}
    ]
    
    {:ok, res} = LlmComposer.run_completion(settings, messages)
    
    # Process the stream and print each parsed chunk
    res.stream
    |> LlmComposer.parse_stream_response()
    |> Enum.each(fn parsed_data ->
      content = get_in(parsed_data, ["message", "content"])
      if content, do: IO.write(content)
    end)
    ```
  """
  @spec parse_stream_response(Enumerable.t()) :: Enumerable.t()
  def parse_stream_response(stream) do
    stream
    |> Stream.filter(fn chunk -> chunk != "[DONE]" end)
    |> Stream.map(fn data ->
      case Jason.decode(data) do
        {:ok, parsed} ->
          parsed

        {:error, _} ->
          nil
      end
    end)
    |> Stream.filter(fn content -> content != nil and content != "" end)
  end

  @spec user_prompt(Settings.t(), String.t(), map()) :: String.t()
  defp user_prompt(settings, message, opts) do
    prompt = Map.get(opts, :user_prompt_prefix, settings.user_prompt_prefix)
    prompt <> message
  end

  @spec maybe_run_functions(LlmResponse.t(), messages(), Settings.t()) :: Helpers.action_result()
  defp maybe_run_functions(res, messages, settings) do
    res
    |> Helpers.maybe_exec_functions(settings.functions)
    |> Helpers.maybe_complete_chat(messages, fn new_messages ->
      run_completion(settings, new_messages, res)
    end)
  end

  @spec validate_settings(Settings.t()) :: :ok
  defp validate_settings(%Settings{
         providers: providers,
         provider: provider,
         provider_opts: provider_opts
       }) do
    cond do
      providers != [] and (provider != nil or (provider_opts != nil and provider_opts != [])) ->
        raise ArgumentError,
              "Settings cannot contain both :providers and deprecated :provider/:provider_opts simultaneously. " <>
                "Please use only :providers. " <>
                "Current settings: providers=#{inspect(providers)}, provider=#{inspect(provider)}"

      provider != nil or (provider_opts != nil and provider_opts != []) ->
        Logger.warning(@deprecated_msg)
        :ok

      true ->
        :ok
    end
  end

  # old case of single provider config
  defp fallback_run(
         messages,
         %{provider: provider, provider_opts: provider_opts} = settings,
         system_msg
       ) do
    provider_opts = get_provider_opts(provider_opts, settings)
    provider.run(messages, system_msg, provider_opts)
  end

  # only one provider in list
  defp fallback_run(
         messages,
         %{providers: [{provider, provider_opts}]} = settings,
         system_msg
       ) do
    provider_opts = get_provider_opts(provider_opts, settings)
    provider.run(messages, system_msg, provider_opts)
  end

  defp fallback_run(messages, %{providers: providers} = settings, system_msg) do
    router = get_provider_router()

    if Process.whereis(router) == nil do
      {:error, :provider_router_not_started}
    else
      Enum.reduce_while(
        providers,
        {:error, :no_providers_available},
        &fallback_run_router(&1, &2, router, messages, system_msg, settings)
      )
    end
  end

  defp fallback_run_router(
         {provider, provider_opts},
         _acc,
         router,
         messages,
         system_msg,
         settings
       ) do
    case router.should_use_provider?(provider) do
      :skip ->
        # Skip this provider and continue
        {:cont, {:error, :provider_skipped}}

      {:delay, _ms} ->
        # You could implement delay logic here, but for now skip
        {:cont, {:error, :provider_skipped}}

      :allow ->
        Logger.debug("#{provider.name()} allowed")
        provider_opts = get_provider_opts(provider_opts, settings)
        run_provider(provider, messages, system_msg, provider_opts, router)
    end
  end

  defp run_provider(provider, messages, system_msg, provider_opts, router) do
    case provider.run(messages, system_msg, provider_opts) do
      {:ok, _res} = ok_res ->
        router.on_provider_success(provider)
        {:halt, ok_res}

      {:error, error} = err_res ->
        case router.on_provider_failure(provider, error) do
          :continue ->
            {:cont, err_res}

          :block ->
            # provider blocked, skip remaining
            {:cont, err_res}

          {:block, _ms} ->
            # block with timer (same handling for now)
            {:cont, err_res}
        end
    end
  end

  defp get_provider_opts(opts, settings) do
    Keyword.merge(opts,
      functions: settings.functions,
      stream_response: settings.stream_response,
      api_key: settings.api_key,
      track_costs: settings.track_costs
    )
  end

  defp get_provider_router do
    :LlmComposer
    |> Application.get_env(:provider_router, [])
    |> Keyword.get(:name, LlmComposer.ProviderRouter.Simple)
  end
end
