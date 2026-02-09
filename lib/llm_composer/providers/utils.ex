defmodule LlmComposer.Providers.Utils do
  @moduledoc false

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

      %Message{type: :assistant, content: message, metadata: metadata} ->
        build_assistant_message(message, metadata)

      %Message{type: :tool_result, content: content, metadata: metadata} ->
        %{
          "role" => "tool",
          "tool_call_id" => metadata["tool_call_id"],
          "content" => to_string(content)
        }

      _other ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  def map_messages(messages, :open_router), do: map_messages(messages, :open_ai)

  def map_messages(messages, :google) do
    messages
    |> Stream.map(fn
      %Message{type: :user, content: message} ->
        %{"role" => "user", "parts" => [%{"text" => message}]}

      %Message{type: :assistant, content: message, metadata: metadata} ->
        build_google_assistant_message(message, metadata)

      %Message{type: :tool_result, content: content, metadata: metadata} ->
        %{
          "role" => "user",
          "parts" => [
            %{
              "functionResponse" => %{
                "name" => metadata["tool_call_id"],
                "response" => %{
                  "result" => to_string(content)
                }
              }
            }
          ]
        }

      _other ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec build_google_assistant_message(String.t() | nil, map()) :: map()
  defp build_google_assistant_message(message, metadata) do
    base_message = %{"role" => "model"}

    case metadata[:tool_calls] do
      nil ->
        Map.put(base_message, "parts", [%{"text" => message}])

      tool_calls ->
        parts =
          Enum.map(tool_calls, fn call ->
            arguments =
              if is_binary(call.arguments) do
                Jason.decode!(call.arguments)
              else
                call.arguments
              end

            %{
              "functionCall" => %{
                "name" => call.name,
                "args" => arguments
              }
            }
          end)

        # Add text part if message is not empty
        parts =
          if message && message != "" do
            [%{"text" => message} | parts]
          else
            parts
          end

        Map.put(base_message, "parts", parts)
    end
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

  @spec merge_request_params(map(), map()) :: map()
  def merge_request_params(base_req, req_params) do
    Enum.reduce(req_params, base_req, fn {key, value}, acc ->
      existing = Map.get(acc, key)

      if is_map(existing) and is_map(value) do
        Map.put(acc, key, Map.merge(existing, value))
      else
        Map.put(acc, key, value)
      end
    end)
  end

  @spec get_tools([LlmComposer.Function.t()] | nil, atom) :: nil | [map()]
  def get_tools(nil, _provider), do: nil

  def get_tools(functions, provider) when is_list(functions) do
    Enum.map(functions, &transform_fn_to_tool(&1, provider))
  end

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
    case Keyword.get(opts, key) do
      nil ->
        :llm_composer
        |> Application.get_env(provider_key, [])
        |> Keyword.get(key, default)

      value ->
        value
    end
  end

  defp transform_fn_to_tool(%LlmComposer.Function{} = function, provider)
       when provider in [:open_ai, :ollama, :open_router] do
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

  @spec build_assistant_message(String.t() | nil, map()) :: map()
  defp build_assistant_message(message, metadata) do
    assistant_msg = %{"role" => "assistant"}

    case metadata[:tool_calls] do
      nil ->
        Map.put(assistant_msg, "content", message)

      tool_calls ->
        formatted_calls =
          Enum.map(tool_calls, fn call ->
            %{
              "id" => call.id,
              "type" => call.type || "function",
              "function" => %{
                "name" => call.name,
                "arguments" => call.arguments
              }
            }
          end)

        assistant_msg
        |> Map.put("content", message)
        |> Map.put("tool_calls", formatted_calls)
    end
  end
end
