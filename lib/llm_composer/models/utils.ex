defmodule LlmComposer.Models.Utils do
  @moduledoc false
  alias LlmComposer.FunctionCall
  alias LlmComposer.Message

  @spec map_messages([Message.t()]) :: [map()]
  def map_messages(messages) do
    messages
    |> Stream.map(fn
      %Message{type: :user, content: message} ->
        %{"role" => "user", "content" => message}

      %Message{type: :system, content: message} when message in ["", nil] ->
        nil

      %Message{type: :system, content: message} ->
        %{"role" => "system", "content" => message}

      # reference to original "tool_calls"
      %Message{type: :assistant, content: nil, metadata: %{original: %{"tool_calls" => _} = msg}} ->
        msg

      %Message{type: :assistant, content: message} ->
        %{"role" => "assistant", "content" => message}

      %Message{
        type: :function_result,
        content: message,
        metadata: %{
          fcall: %FunctionCall{
            id: call_id
          }
        }
      } ->
        %{"role" => "tool", "content" => message, "tool_call_id" => call_id}
    end)
    |> Enum.reject(&is_nil/1)
  end
end
