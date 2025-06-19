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
    model: LlmComposer.Models.OpenAI,
    model_opts: [model: "gpt-4o-mini"],
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
    system_msg = Message.new(:system, settings.system_prompt)

    model_opts =
      Keyword.merge(settings.model_opts, functions: settings.functions, api_key: settings.api_key)

    messages
    |> settings.model.run(system_msg, model_opts)
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
end
