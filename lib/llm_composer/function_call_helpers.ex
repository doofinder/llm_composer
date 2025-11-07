defmodule LlmComposer.FunctionCallHelpers do
  @moduledoc """
  Helpers for building assistant messages and tool-result messages when handling
  function (tool) calls returned by LLM providers.

  This module provides a default implementation for composing the assistant
  message that preserves the original assistant response and attaches the
  `tool_calls` metadata. Providers can optionally implement
  `build_assistant_with_tools/3` to customize behavior.
  """

  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @doc """
  Build an assistant message that preserves the original assistant response and
  attaches `tool_calls` so it can be sent back to the provider along with
  tool result messages.

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
        metadata: %{
          original: resp.main_response.metadata[:original],
          tool_calls: resp.function_calls
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
        content: to_string(call.result),
        metadata: %{"tool_call_id" => call.id}
      }
    end)
  end
end
