defmodule LlmComposer do
  @moduledoc false

  alias LlmComposer.Helpers
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message
  alias LlmComposer.Settings

  require Logger

  @type response :: {:ok, LlmResponse.t()} | {:error, term()}

  @spec simple_chat(Settings.t(), String.t()) :: response()
  def simple_chat(%Settings{} = settings, msg) do
    messages = get_messages(settings, msg, [], %{})

    run_completion(settings, messages, settings)
  end

  @spec run_completion(Settings.t(), [Message.t()], LlmResponse.t() | nil) :: response()
  def run_completion(settings, messages, previous_response \\ nil) do
    system_msg = Message.new(:system, settings.system_prompt)
    model_opts = Keyword.merge(settings.model_opts, functions: settings.functions)

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

      {:error, data} = resp ->
        Logger.error("error in llm call: #{inspect(data)}")
        resp
    end)
  end

  @spec get_messages(Settings.t(), binary, [map()], map()) :: [map()]
  defp get_messages(settings, current_message, old_messages, opts) do
    old_messages ++ [Message.new(:user, user_prompt(settings, current_message, opts))]
  end

  @doc false
  @spec user_prompt(Settings.t(), binary, map()) :: binary
  defp user_prompt(settings, message, opts) do
    prompt = Map.get(opts, :user_prompt_prefix, settings.user_prompt_prefix)
    prompt <> message
  end

  @spec maybe_run_functions(LlmResponse.t(), [Message.t()], Settings.t()) :: term()
  defp maybe_run_functions(res, messages, settings) do
    res
    |> Helpers.maybe_exec_functions(settings.functions)
    |> Helpers.maybe_complete_chat(messages, fn new_messages ->
      run_completion(settings, new_messages, res)
    end)
  end
end
