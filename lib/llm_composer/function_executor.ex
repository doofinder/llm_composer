defmodule LlmComposer.FunctionExecutor do
  @moduledoc """
  Provides manual execution of function calls from LLM responses.

  This module allows users to explicitly execute individual function calls
  returned by the LLM, without automatic execution. It's designed for manual
  control over function invocation and result handling.

  ## Usage

  After receiving a response with function calls, use `execute/2` to
  manually execute each function call with its arguments parsed and
  validated before invocation.
  """

  alias LlmComposer.Function
  alias LlmComposer.FunctionCall

  @json_mod if Code.ensure_loaded?(JSON), do: JSON, else: Jason

  @doc """
  Executes a single function call and returns the updated FunctionCall with result.

  ## Parameters
    - `function_call`: The FunctionCall struct to execute
    - `functions`: List of Function definitions available for execution

  ## Returns
    - `{:ok, executed_call}`: FunctionCall with result populated
    - `{:error, reason}`: Error tuple if execution fails

  ## Possible Errors
    - `{:error, :function_not_found}`: Named function not in definitions
    - `{:error, {:invalid_arguments, reason}}`: Failed to parse JSON arguments
    - `{:error, {:execution_failed, reason}}`: Exception during function execution
  """
  @spec execute(FunctionCall.t(), [Function.t()]) ::
          {:ok, FunctionCall.t()} | {:error, term()}
  def execute(function_call, functions) when is_list(functions) do
    with {:ok, function} <- find_function(function_call.name, functions),
         {:ok, args} <- parse_arguments(function_call.arguments),
         {:ok, result} <- invoke_function(function, args) do
      executed_call = %FunctionCall{function_call | result: result}
      {:ok, executed_call}
    end
  end

  @spec find_function(String.t(), [Function.t()]) ::
          {:ok, Function.t()} | {:error, :function_not_found}
  defp find_function(name, functions) do
    case Enum.find(functions, fn f -> f.name == name end) do
      nil -> {:error, :function_not_found}
      function -> {:ok, function}
    end
  end

  @spec parse_arguments(String.t() | nil) :: {:ok, map()} | {:error, term()}
  defp parse_arguments(nil) do
    {:ok, %{}}
  end

  defp parse_arguments(arguments) when is_binary(arguments) do
    parsed = @json_mod.decode!(arguments)
    {:ok, parsed}
  rescue
    e -> {:error, {:invalid_arguments, Exception.message(e)}}
  end

  @spec invoke_function(Function.t(), map()) :: {:ok, term()} | {:error, term()}
  defp invoke_function(function, args) do
    {module, function_name} = function.mf

    try do
      result = apply(module, function_name, [args])
      {:ok, result}
    rescue
      e -> {:error, {:execution_failed, Exception.message(e)}}
    catch
      type, value -> {:error, {:execution_failed, "#{type}: #{inspect(value)}"}}
    end
  end
end
