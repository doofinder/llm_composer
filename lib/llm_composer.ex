defmodule LlmComposer do
  @moduledoc """
  `LlmComposer` is responsible for interacting with a language model to perform chat-related operations,
  such as running completions and generating responses.

  ## Example Usage

  To use `LlmComposer` for creating a simple chat interaction with a language model, define a settings configuration and initiate a chat:

  ```elixir
  # Define the settings for your LlmComposer instance
  settings = %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.OpenAI,  [model: "gpt-4.1-mini"]}
    ],
    system_prompt: "You are a helpful assistant.",
    user_prompt_prefix: "",
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

  alias LlmComposer.LlmResponse
  alias LlmComposer.Message
  alias LlmComposer.ProvidersRunner
  alias LlmComposer.Settings

  require Logger

  @json_mod if Code.ensure_loaded?(JSON), do: JSON, else: Jason

  @type messages :: [Message.t()]

  @doc """
  Initiates a simple chat interaction with the language model.

  ## Parameters
    - `settings`: The settings for the language model, including prompts and options.
    - `msg`: The user message to be sent to the language model.

  ## Returns
    - The result of the language model's response.
  """
  @spec simple_chat(Settings.t(), String.t()) :: {:ok, LlmResponse.t()} | {:error, term()}
  def simple_chat(%Settings{} = settings, msg) do
    messages = [Message.new(:user, user_prompt(settings, msg, %{}))]

    run_completion(settings, messages)
  end

  @doc """
  Runs the completion process by sending messages to the language model and handling the response.

  ## Parameters
    - `settings`: The settings for the language model, including prompts and model options.
    - `messages`: The list of messages to be sent to the language model.
    - `previous_response` (optional): The previous response object, if any, used for context.

  ## Returns
    - A tuple containing `:ok` with the response or `:error` if the model call fails.
  """
  @spec run_completion(Settings.t(), messages(), LlmResponse.t() | nil) ::
          {:ok, LlmResponse.t()} | {:error, term()}
  def run_completion(settings, messages, previous_response \\ nil) do
    system_msg = Message.new(:system, settings.system_prompt)

    messages
    |> ProvidersRunner.run(settings, system_msg)
    |> then(fn
      {:ok, res} ->
        # set previous response all the time
        res = %LlmResponse{res | previous_response: previous_response}

        Logger.debug("input_tokens=#{res.input_tokens}, output_tokens=#{res.output_tokens}")

        {:ok, res}

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
    |> Stream.map(fn data -> @json_mod.decode!(data) end)
    |> Stream.filter(fn content -> content != nil and content != "" end)
  end

  @spec user_prompt(Settings.t(), String.t(), map()) :: String.t()
  defp user_prompt(settings, message, opts) do
    prompt = Map.get(opts, :user_prompt_prefix, settings.user_prompt_prefix)
    prompt <> message
  end
end
