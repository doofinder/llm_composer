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
  alias LlmComposer.ProviderStreamChunk
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
  Parses a provider stream into normalized `LlmComposer.StreamChunk` structs.

  ## Parameters
    - `stream`: The raw streaming enumerable produced by the provider response.
    - `provider`: The atom identifying the provider that produced the stream.
    - `opts`: Additional parsing options (currently unused).

  ## Returns
    - A stream of `%LlmComposer.StreamChunk{}` values that include the original raw chunk,
      categorized event type, optional usage data, and normalized metadata.

  ## Example

    ```elixir
    {:ok, res} = LlmComposer.run_completion(settings, messages)

    res.stream
    |> LlmComposer.parse_stream_response(res.provider)
    |> Enum.each(fn chunk ->
      IO.write(chunk.text || "")
    end)
    ```
  """
  @spec parse_stream_response(Enumerable.t(), atom(), keyword()) :: Enumerable.t()
  def parse_stream_response(stream, provider, opts \\ []) do
    stream
    |> Stream.flat_map(&split_stream_lines/1)
    |> Stream.map(&extract_stream_payload/1)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.map(fn {:ok, payload} -> wrap_stream_chunk(payload, provider, opts) end)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.map(fn {:ok, chunk} -> chunk end)
  end

  defp split_stream_lines(value) when is_binary(value) do
    value
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp split_stream_lines(_), do: []

  defp extract_stream_payload(line) when is_binary(line) do
    line = String.trim(line)

    cond do
      line in ["", "[DONE]", "data: [DONE]"] ->
        :skip

      String.starts_with?(line, "data:") ->
        payload =
          line
          |> String.trim_leading("data:")
          |> String.trim_leading()

        decode_stream_chunk(payload)

      true ->
        decode_stream_chunk(line)
    end
  end

  defp extract_stream_payload(_), do: :skip

  defp decode_stream_chunk(value) do
    case @json_mod.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> :skip
    end
  end

  defp wrap_stream_chunk(payload, provider, opts) do
    case provider_stream_struct(provider, payload, opts) do
      {:error, _} = error -> error
      struct -> ProviderStreamChunk.to_stream_chunk(struct, opts)
    end
  end

  defp provider_stream_struct(:open_ai, payload, opts),
    do: ProviderStreamChunk.OpenAI.new(payload, opts)

  defp provider_stream_struct(:open_router, payload, opts),
    do: ProviderStreamChunk.OpenRouter.new(payload, opts)

  defp provider_stream_struct(:open_ai_responses, payload, opts),
    do: ProviderStreamChunk.OpenAIResponses.new(payload, opts)

  defp provider_stream_struct(:google, payload, opts),
    do: ProviderStreamChunk.Google.new(payload, opts)

  defp provider_stream_struct(:ollama, payload, opts),
    do: ProviderStreamChunk.Ollama.new(payload, opts)

  defp provider_stream_struct(provider, _payload, _opts) do
    {:error, %{reason: :unsupported_stream_provider, provider: provider}}
  end

  @spec user_prompt(Settings.t(), String.t(), map()) :: String.t()
  defp user_prompt(settings, message, opts) do
    prompt = Map.get(opts, :user_prompt_prefix, settings.user_prompt_prefix)
    prompt <> message
  end
end
