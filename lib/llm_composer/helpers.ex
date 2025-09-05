defmodule LlmComposer.Helpers do
  @moduledoc """
  Provides helper functions for the `LlmComposer` module, particularly for managing
  function calls and handling language model responses.

  These helpers are designed to execute functions as part of the response processing pipeline,
  manage completions, and log relevant information for debugging.
  """

  alias LlmComposer.Function
  alias LlmComposer.FunctionCall
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  require Logger

  @json_mod if Code.ensure_loaded?(JSON), do: JSON, else: Jason

  @type messages :: [term()]
  @type llmfunctions :: [Function.t()]
  @type action_result ::
          {:ok, LlmResponse.t()}
          | {:completion, LlmResponse.t(), llmfunctions()}
          | {:error, term()}

  @doc """
  Executes the functions specified in the language model response, if any.

  ## Parameters
    - `res`: The language model response containing actions to be executed.
    - `llm_functions`: A list of functions available for execution.

  ## Returns
    - `{:ok, res}` if no actions are found in the response.
    - `{:completion, res, results}` if actions are executed, returning the completion status and results.
  """
  @spec maybe_exec_functions(LlmResponse.t(), llmfunctions()) :: action_result()
  def maybe_exec_functions(%{actions: []} = res, _functions), do: {:ok, res}

  def maybe_exec_functions(%{actions: [actions | _tail]} = res, llm_functions) do
    results = Enum.map(actions, &exec_function(&1, llm_functions))

    {:completion, res, results}
  end

  @doc """
  Completes the chat flow by appending function results to the messages and re-running the completion process.

  ## Parameters
    - `action_result`: The result of a previous action or completion.
    - `messages`: The list of messages exchanged so far.
    - `run_completion_fn`: A function to re-run the completion with updated messages.

  ## Returns
    - The result of re-running the completion with the new set of messages and function results.
  """
  @spec maybe_complete_chat(action_result(), messages(), function()) :: action_result()
  def maybe_complete_chat({:ok, _action_result} = res, _messages, _fcalls), do: res

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

  defp serialize_fcall_result(res) when is_map(res) or is_list(res), do: @json_mod.encode!(res)
  defp serialize_fcall_result(res) when is_binary(res) or is_tuple(res), do: res
  defp serialize_fcall_result(res), do: "#{res}"
end
