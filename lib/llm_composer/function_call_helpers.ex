defmodule LlmComposer.FunctionCallHelpers do
  @moduledoc """
  Helpers for building assistant messages and tool-result messages when handling
  function (tool) calls returned by LLM providers.

  This module provides a default implementation for composing the assistant
  message that preserves the original assistant response and its function calls.
  Providers can optionally implement `build_assistant_with_tools/3` to customize
  behavior.
  """

  alias LlmComposer.Helpers
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @doc """
  Build an assistant message that preserves the original assistant response and
  its function calls so it can be sent back to the provider along with tool
  result messages.

  If `provider_mod` exports `build_assistant_with_tools/3`, this function will
  delegate to that implementation; otherwise it uses a sensible default.
  """
  @spec build_assistant_with_tools(module(), LlmResponse.t(), Message.t(), keyword()) ::
          Message.t()
  def build_assistant_with_tools(
        provider_mod,
        %LlmResponse{} = resp,
        %Message{} = user_msg,
        opts \\ []
      ) do
    if function_exported?(provider_mod, :build_assistant_with_tools, 3) do
      provider_mod.build_assistant_with_tools(resp, user_msg, opts)
    else
      %Message{
        type: :assistant,
        content: resp.main_response.content || "Using tool results",
        function_calls: resp.main_response.function_calls,
        metadata: %{
          original: resp.main_response.metadata[:original]
        }
      }
    end
  end

  @doc """
  Convert executed function-call results into `:tool_result` messages which
  include the mapping back to the tool call id in `metadata["tool_call_id"]`.
  """
  @spec build_tool_result_messages(list()) :: list(Message.t())
  def build_tool_result_messages(executed_calls) when is_list(executed_calls) do
    Enum.map(executed_calls, fn call ->
      %Message{
        type: :tool_result,
        content: result_to_content(call.result),
        metadata: %{"tool_call_id" => call.id}
      }
    end)
  end

  @spec result_to_content(term()) :: String.t()
  defp result_to_content(result) when is_binary(result), do: result

  defp result_to_content(result) do
    Helpers.json_engine().encode!(result)
  rescue
    _ -> inspect(result)
  end
end
