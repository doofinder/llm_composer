defmodule LlmComposer.Helpers do
  @moduledoc """
  Function helpers for Caller macro module.

  Functions that can be seen in a error stack trace if something fails.
  """

  alias LlmComposer.Function
  alias LlmComposer.FunctionCall
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  require Logger

  @type messages :: [term()]
  @type llmfunctions :: [Function.t()]
  @type action_result ::
          {:ok, LlmResponse.t()}
          | {:completion, LlmResponse.t(), llmfunctions()}
          | {:error, term()}

  @spec maybe_exec_functions(LlmResponse.t(), llmfunctions()) :: action_result()
  def maybe_exec_functions(%{actions: []} = res, _functions), do: {:ok, res}

  def maybe_exec_functions(%{actions: [actions | _]} = res, llm_functions) do
    results = Enum.map(actions, &exec_function(&1, llm_functions))

    {:completion, res, results}
  end

  @spec maybe_complete_chat(action_result(), messages(), function()) :: action_result()
  def maybe_complete_chat({:ok, _} = res, _messages, _fcalls), do: res

  def maybe_complete_chat({:completion, oldres, results}, messages, run_completion_fn) do
    results =
      Enum.map(
        results,
        &Message.new(:function_result, serialize_fcall_result(&1.result), %{fcall: &1})
      )

    new_messages = messages ++ [oldres.main_response] ++ results

    run_completion_fn.(new_messages)
  end

  @spec exec_function(fcall :: FunctionCall.t(), functions :: llmfunctions()) :: FunctionCall.t()
  defp exec_function(%FunctionCall{} = fcall, functions) do
    [
      %{
        mf: {mod, fname}
      }
    ] = Enum.filter(functions, fn function -> function.name == fcall.name end)

    mod_str =
      mod
      |> Atom.to_string()
      |> String.trim_leading("Elixir.")

    Logger.debug("running function #{mod_str}.#{fname}")
    res = apply(mod, fname, [fcall.arguments])

    %FunctionCall{fcall | result: res}
  end

  defp serialize_fcall_result(res) when is_map(res) or is_list(res), do: Jason.encode!(res)
  defp serialize_fcall_result(res) when is_binary(res), do: res
  defp serialize_fcall_result(res), do: "#{res}"
end
