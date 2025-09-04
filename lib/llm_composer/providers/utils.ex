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
      %Message{
        type: :assistant,
        content: nil,
        metadata: %{original: %{"tool_calls" => _tool_calls} = msg}
      } ->
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

      # reference to original "tool_calls"
      %Message{
        type: :assistant,
        content: nil,
        metadata: %{original: %{"parts" => [%{"functionCall" => _}]} = msg}
      } ->
        msg

      %Message{type: :assistant, content: message} ->
        %{"role" => "model", "parts" => [%{"text" => message}]}

      %Message{
        type: :function_result,
        content: message,
        metadata: %{
          fcall: %FunctionCall{
            name: name
          }
        }
      } ->
        %{
          "role" => "user",
          "parts" => [
            %{"functionResponse" => %{"name" => name, "response" => %{"result" => message}}}
          ]
        }
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

  @spec get_tools([LlmComposer.Function.t()] | nil, atom) :: nil | [map()]
  def get_tools(nil, _provider), do: nil

  def get_tools(functions, provider) when is_list(functions) do
    Enum.map(functions, &transform_fn_to_tool(&1, provider))
  end

  @spec extract_actions(map()) :: nil | []
  def extract_actions(%{"choices" => choices}) when is_list(choices) do
    choices
    |> Enum.filter(&(&1["finish_reason"] == "tool_calls"))
    |> Enum.map(&get_action/1)
  end

  # google case
  def extract_actions(%{"candidates" => candidates}) when is_list(candidates) do
    candidates
    |> Enum.filter(fn
      %{"finishReason" => "STOP", "content" => %{"parts" => [%{"functionCall" => _data}]}} -> true
      _other -> false
    end)
    |> Enum.map(&get_action(&1, :google))
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

  @doc """
  Reads a configuration value for the given provider key.

  Priority order:
  1. Get from `opts` keyword list.
  2. Get from application config `:llm_composer`, provider_key.
  3. Use provided `default` value.
  """
  @spec get_config(atom, atom, keyword, any) :: any
  def get_config(provider_key, key, opts, default \\ nil) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        value

      :error ->
        :llm_composer
        |> Application.get_env(provider_key, [])
        |> Keyword.get(key, default)
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

  defp get_action(%{"content" => %{"parts" => parts}}, :google) do
    Enum.map(parts, fn
      %{"functionCall" => fcall} ->
        %FunctionCall{
          type: "function",
          id: nil,
          name: fcall["name"],
          arguments: fcall["args"]
        }
    end)
  end

  defp transform_fn_to_tool(%LlmComposer.Function{} = function, provider)
       when provider in [:open_ai, :ollama] do
    %{
      type: "function",
      function: %{
        "name" => function.name,
        "description" => function.description,
        "parameters" => function.schema
      }
    }
  end

  defp transform_fn_to_tool(%LlmComposer.Function{} = function, :google) do
    %{
      "name" => function.name,
      "description" => function.description,
      "parameters" => function.schema
    }
  end
end
