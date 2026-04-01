defmodule LlmComposer.Providers.Utils do
  @moduledoc false

  alias LlmComposer.Helpers
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

      %Message{type: :assistant, content: message, function_calls: function_calls} ->
        build_assistant_message(message, function_calls)

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

  def map_messages(messages, :open_router) do
    messages
    |> Stream.map(fn
      %Message{type: :user, content: message} ->
        %{"role" => "user", "content" => message}

      %Message{type: :system, content: message} when message in ["", nil] ->
        nil

      %Message{type: :system, content: message} ->
        %{"role" => "system", "content" => message}

      %Message{
        type: :assistant,
        content: message,
        function_calls: function_calls,
        reasoning: reasoning,
        reasoning_details: reasoning_details
      } ->
        message
        |> build_assistant_message(function_calls)
        |> maybe_put("reasoning", reasoning)
        |> maybe_put("reasoning_details", reasoning_details)

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

  def map_messages(messages, :google) do
    messages
    |> Stream.map(fn
      %Message{type: :user, content: message} ->
        %{"role" => "user", "parts" => [%{"text" => message}]}

      %Message{
        type: :assistant,
        content: message,
        function_calls: function_calls,
        metadata: metadata
      } ->
        build_google_assistant_message(message, function_calls, metadata)

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
    |> merge_consecutive_function_responses()
  end

  @spec build_google_assistant_message(
          String.t() | nil,
          [LlmComposer.FunctionCall.t()] | nil,
          map()
        ) :: map()
  defp build_google_assistant_message(message, function_calls, metadata) do
    # When the original response content is available, use its parts directly
    # to preserve fields like thought_signature that Gemini thinking models require.
    case metadata[:original] do
      %{"parts" => parts} when is_list(parts) ->
        %{"role" => "model", "parts" => parts}

      _ ->
        build_google_assistant_parts(message, function_calls)
    end
  end

  @spec build_google_assistant_parts(String.t() | nil, [LlmComposer.FunctionCall.t()] | nil) ::
          map()
  defp build_google_assistant_parts(message, nil) do
    %{"role" => "model", "parts" => [%{"text" => message}]}
  end

  defp build_google_assistant_parts(message, tool_calls) when is_list(tool_calls) do
    call_parts =
      Enum.map(tool_calls, fn call ->
        arguments =
          if is_binary(call.arguments) do
            Helpers.json_engine().decode!(call.arguments)
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

    parts =
      if message && message != "" do
        [%{"text" => message} | call_parts]
      else
        call_parts
      end

    %{"role" => "model", "parts" => parts}
  end

  # Merges consecutive tool-result user messages into a single content block.
  # Google requires all functionResponse parts for one model turn to be in one "user" turn.
  @spec merge_consecutive_function_responses([map()]) :: [map()]
  defp merge_consecutive_function_responses(messages) do
    messages
    |> Enum.reduce([], fn
      %{"role" => "user", "parts" => [%{"functionResponse" => _} | _] = parts} = _msg,
      [%{"role" => "user", "parts" => [%{"functionResponse" => _} | _] = prev_parts} | rest] ->
        [%{"role" => "user", "parts" => prev_parts ++ parts} | rest]

      msg, acc ->
        [msg | acc]
    end)
    |> Enum.reverse()
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
  @spec get_open_ai_key(keyword()) :: String.t()
  def get_open_ai_key(opts) do
    case get_config(:open_ai, :api_key, opts) do
      nil -> raise LlmComposer.Errors.MissingKeyError
      key -> key
    end
  end

  @spec get_open_ai_request_opts(keyword()) :: keyword()
  def get_open_ai_request_opts(opts) do
    timeout = Keyword.get(opts, :timeout, Application.get_env(:llm_composer, :timeout, 50_000))
    adapter_opts = [receive_timeout: timeout]

    opts
    |> get_req_opts()
    |> Keyword.update(:adapter, adapter_opts, &Keyword.merge(&1, adapter_opts))
  end

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
       when provider in [:open_ai, :open_ai_responses, :ollama, :open_router] do
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

  @spec maybe_put(map(), String.t(), any()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec build_assistant_message(String.t() | nil, [LlmComposer.FunctionCall.t()] | nil) :: map()
  defp build_assistant_message(message, nil) do
    %{"role" => "assistant", "content" => message}
  end

  defp build_assistant_message(message, tool_calls) when is_list(tool_calls) do
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

    %{"role" => "assistant", "content" => message, "tool_calls" => formatted_calls}
  end
end
