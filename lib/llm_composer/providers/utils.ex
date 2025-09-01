defmodule LlmComposer.Providers.Utils do
  @moduledoc false

  alias LlmComposer.FunctionCall
  alias LlmComposer.Message

  @spec map_messages([Message.t()], atom) :: [map()]
  def map_messages(messages, provider \\ :open_ai)

  def map_messages(messages, :open_ai) do
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

  def map_messages(messages, :google) do
    messages
    |> Stream.map(fn
      %Message{type: :user, content: message} ->
        %{"role" => "user", "parts" => [%{"text" => message}]}

      %Message{type: :assistant, content: message} ->
        %{"role" => "model", "parts" => [%{"text" => message}]}
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec cleanup_body(map()) :: map()
  def cleanup_body(body) do
    body
    |> Enum.reject(fn
      {_param, nil} -> true
      {_param, []} -> true
      _other -> false
    end)
    |> Map.new()
  end

  @spec get_tools([LlmComposer.Function.t()] | nil) :: nil | [map()]
  def get_tools(nil), do: nil

  def get_tools(functions) when is_list(functions) do
    Enum.map(functions, &transform_fn_to_tool/1)
  end

  @spec extract_actions(map()) :: nil | []
  def extract_actions(%{"choices" => choices}) when is_list(choices) do
    choices
    |> Enum.filter(&(&1["finish_reason"] == "tool_calls"))
    |> Enum.map(&get_action/1)
  end

  def extract_actions(_response), do: []

  @spec get_req_opts(keyword()) :: keyword()
  def get_req_opts(opts) do
    if Keyword.get(opts, :stream_response) do
      [adapter: [response: :stream]]
    else
      []
    end
  end

  defp get_action(%{"message" => %{"tool_calls" => calls}}) do
    Enum.map(calls, fn call ->
      %FunctionCall{
        type: "function",
        id: call["id"],
        name: call["function"]["name"],
        arguments: Jason.decode!(call["function"]["arguments"])
      }
    end)
  end

  defp transform_fn_to_tool(%LlmComposer.Function{} = function) do
    %{
      type: "function",
      function: %{
        "name" => function.name,
        "description" => function.description,
        "parameters" => function.schema
      }
    }
  end
end
