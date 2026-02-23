defmodule LlmComposer.FunctionCallExtractors do
  @moduledoc false

  alias LlmComposer.FunctionCall

  @spec from_tool_calls(map()) :: [FunctionCall.t()] | nil
  def from_tool_calls(%{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    Enum.map(tool_calls, &build_tool_call/1)
  end

  def from_tool_calls(_), do: nil

  defp build_tool_call(tool_call) do
    function_info = tool_call["function"]

    %FunctionCall{
      id: tool_call["id"],
      name: function_info["name"],
      arguments: function_info["arguments"],
      type: tool_call["type"],
      metadata: %{},
      result: nil
    }
  end

  @spec from_google_parts(map()) :: [FunctionCall.t()] | nil
  def from_google_parts(%{"parts" => parts}) when is_list(parts) do
    function_calls =
      parts
      |> Enum.filter(&Map.has_key?(&1, "functionCall"))
      |> Enum.map(fn part ->
        function_call = part["functionCall"]

        %FunctionCall{
          id: function_call["name"],
          name: function_call["name"],
          arguments: Jason.encode!(function_call["args"] || %{}),
          type: "function",
          metadata: %{},
          result: nil
        }
      end)

    case function_calls do
      [] -> nil
      calls -> calls
    end
  end

  def from_google_parts(_), do: nil
end
