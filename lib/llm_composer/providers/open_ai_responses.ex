defmodule LlmComposer.Providers.OpenAIResponses do
  @moduledoc """
  Provider implementation for OpenAI Responses API.

  Uses the `/responses` endpoint which supports reasoning models and a richer
  input/output format compared to the standard chat completions API.

  Reference: https://platform.openai.com/docs/api-reference/responses
  """
  @behaviour LlmComposer.Provider

  alias LlmComposer.HttpClient
  alias LlmComposer.ProviderResponse
  alias LlmComposer.Providers.Utils

  require Logger

  @impl LlmComposer.Provider
  def name, do: :open_ai_responses

  @impl LlmComposer.Provider
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)
    api_key = Utils.get_open_ai_key(opts)
    base_url = Utils.get_config(:open_ai, :url, opts, "https://api.openai.com/v1")
    client = HttpClient.client(base_url, opts)
    headers = [{"Authorization", "Bearer " <> api_key}]
    req_opts = Utils.get_open_ai_request_opts(opts)

    if model do
      messages
      |> build_request(system_message, model, opts)
      |> log_request_debug(model)
      |> then(&Tesla.post(client, "/responses", &1, headers: headers, opts: req_opts))
      |> handle_response()
      |> wrap_response(opts)
    else
      {:error, :model_not_provided}
    end
  end

  @spec build_request([LlmComposer.Message.t()], LlmComposer.Message.t(), String.t(), keyword()) ::
          map()
  defp build_request(messages, system_message, model, opts) do
    tools =
      opts
      |> Keyword.get(:functions)
      |> format_tools()

    tool_choice = Keyword.get(opts, :tool_choice)

    base_request = %{
      model: model,
      tools: tools,
      tool_choice: tool_choice,
      input: map_messages_to_input([system_message | messages])
    }

    req_params = Keyword.get(opts, :request_params, %{})

    base_request
    |> Utils.merge_request_params(req_params)
    |> maybe_add_reasoning(opts)
    |> maybe_structured_output(opts)
    |> Utils.cleanup_body()
  end

  @spec handle_response(Tesla.Env.result()) :: {:ok, map()} | {:error, term()}
  defp handle_response({:ok, %Tesla.Env{status: 200, body: body}}) do
    Logger.debug("[open_ai_responses] successful response")
    {:ok, %{response: normalize_body(body)}}
  end

  defp handle_response({:ok, resp}) do
    Logger.warning(
      "[open_ai_responses] non-200 response (status=#{Map.get(resp, :status, :unknown)})"
    )

    {:error, resp}
  end

  defp handle_response({:error, reason}) do
    Logger.error("[open_ai_responses] request failed (reason=#{inspect(reason)})")
    {:error, reason}
  end

  @spec wrap_response({:ok, map()} | {:error, term()}, keyword()) ::
          {:ok, LlmComposer.LlmResponse.t()} | {:error, term()}
  defp wrap_response(result, opts) do
    result
    |> ProviderResponse.OpenAIResponses.new(opts)
    |> ProviderResponse.to_llm_response(opts)
  end

  # Maps messages into the Responses API `input` format.
  @spec map_messages_to_input([LlmComposer.Message.t()]) :: list()
  defp map_messages_to_input(messages) do
    messages
    |> Utils.map_messages(:open_ai)
    |> Enum.flat_map(&to_responses_input_items/1)
  end

  # Normalizes the Responses API body into the chat completions shape so the
  # existing `Parser.OpenAI` can handle it without changes.
  @spec normalize_body(map()) :: map()
  defp normalize_body(body) do
    output_items = body["output"] || []
    tool_calls = extract_tool_calls(output_items)
    text = extract_response_text(body, output_items)
    message_content = normalize_message_content(text, tool_calls)

    message =
      maybe_put_tool_calls(%{"role" => "assistant", "content" => message_content}, tool_calls)

    usage = normalize_usage(body["usage"] || %{})

    %{
      "model" => body["model"],
      "choices" => [
        %{"message" => message}
      ],
      "usage" => usage
    }
  end

  @spec extract_response_text(map(), list()) :: String.t()
  defp extract_response_text(body, output_items) do
    case body["output_text"] do
      t when is_binary(t) and t != "" -> t
      _ -> extract_text_from_output(output_items)
    end
  end

  @spec normalize_usage(map()) :: map()
  defp normalize_usage(usage) do
    %{
      "prompt_tokens" => usage["input_tokens"] || 0,
      "completion_tokens" => usage["output_tokens"] || 0,
      "total_tokens" => usage["total_tokens"] || 0
    }
  end

  @spec extract_text_from_output(list()) :: String.t()
  defp extract_text_from_output(output_items) do
    output_items
    |> Enum.flat_map(&Map.get(&1, "content", []))
    |> Enum.map_join("", &Map.get(&1, "text", ""))
  end

  @spec to_responses_input_items(map()) :: [map()]
  defp to_responses_input_items(%{
         "role" => "tool",
         "tool_call_id" => call_id,
         "content" => content
       }) do
    [%{type: "function_call_output", call_id: call_id, output: to_string(content)}]
  end

  defp to_responses_input_items(%{
         "role" => role,
         "content" => content,
         "tool_calls" => tool_calls
       })
       when is_binary(role) and is_list(tool_calls) do
    assistant_message = %{
      type: "message",
      role: role,
      content: normalize_role_content(role, content)
    }

    function_calls =
      Enum.map(tool_calls, fn tool_call ->
        call_id = tool_call["id"]

        %{
          type: "function_call",
          call_id: call_id,
          name: get_in(tool_call, ["function", "name"]),
          arguments: get_in(tool_call, ["function", "arguments"]) || "{}"
        }
      end)

    [assistant_message | function_calls]
  end

  defp to_responses_input_items(%{"role" => role, "content" => content}) when is_binary(role) do
    [
      %{
        type: "message",
        role: role,
        content: normalize_role_content(role, content)
      }
    ]
  end

  defp to_responses_input_items(other), do: [other]

  @spec to_input_content(String.t() | list() | nil) :: list()
  defp to_input_content(content) when is_binary(content),
    do: [%{type: "input_text", text: content}]

  defp to_input_content(content) when is_list(content), do: content
  defp to_input_content(_), do: []

  @spec normalize_role_content(String.t(), String.t() | list() | nil) :: String.t() | list()
  defp normalize_role_content("assistant", content) when is_binary(content), do: content

  defp normalize_role_content("assistant", content) when is_list(content) do
    Enum.map_join(content, "", fn
      %{"text" => text} when is_binary(text) -> text
      %{text: text} when is_binary(text) -> text
      _ -> ""
    end)
  end

  defp normalize_role_content("assistant", _), do: ""
  defp normalize_role_content(_role, content), do: to_input_content(content)

  @spec format_tools([LlmComposer.Function.t()] | nil) :: [map()] | nil
  defp format_tools(nil), do: nil

  defp format_tools(functions) when is_list(functions) do
    Enum.map(functions, fn function ->
      %{
        type: "function",
        name: function.name,
        description: function.description,
        parameters: function.schema,
        strict: true
      }
    end)
  end

  @spec extract_tool_calls(list()) :: [map()] | nil
  defp extract_tool_calls(output_items) when is_list(output_items) do
    tool_calls =
      output_items
      |> Enum.filter(&(Map.get(&1, "type") == "function_call"))
      |> Enum.map(fn item ->
        %{
          "id" => item["call_id"] || item["id"],
          "type" => "function",
          "function" => %{
            "name" => item["name"],
            "arguments" => normalize_arguments(item["arguments"])
          }
        }
      end)

    case tool_calls do
      [] -> nil
      calls -> calls
    end
  end

  defp extract_tool_calls(_), do: nil

  @spec normalize_arguments(any()) :: String.t()
  defp normalize_arguments(args) when is_binary(args), do: args
  defp normalize_arguments(args) when is_map(args), do: Jason.encode!(args)
  defp normalize_arguments(_), do: "{}"

  @spec normalize_message_content(String.t(), [map()] | nil) :: String.t() | nil
  defp normalize_message_content(text, tool_calls) do
    if text == "" and is_list(tool_calls), do: nil, else: text
  end

  @spec maybe_put_tool_calls(map(), [map()] | nil) :: map()
  defp maybe_put_tool_calls(message, nil), do: message
  defp maybe_put_tool_calls(message, tool_calls), do: Map.put(message, "tool_calls", tool_calls)

  @spec maybe_add_reasoning(map(), keyword()) :: map()
  defp maybe_add_reasoning(request, opts) do
    case Keyword.get(opts, :reasoning_effort) do
      nil ->
        request

      effort when is_binary(effort) ->
        updated =
          request
          |> Map.get(:reasoning, %{})
          |> Map.put(:effort, effort)

        Map.put(request, :reasoning, updated)
    end
  end

  @spec maybe_structured_output(map(), keyword()) :: map()
  defp maybe_structured_output(base_request, opts) do
    response_schema = Keyword.get(opts, :response_schema)

    if is_map(response_schema) do
      Map.put_new(base_request, :text, %{
        "format" => %{
          "type" => "json_schema",
          "name" => "response",
          "strict" => true,
          "schema" => response_schema
        }
      })
    else
      base_request
    end
  end

  @spec log_request_debug(map(), String.t()) :: map()
  defp log_request_debug(request, model) do
    timeout = Application.get_env(:llm_composer, :timeout, 50_000)

    Logger.debug(
      "[open_ai_responses] sending request (model=#{model}, timeout_ms=#{timeout}, reasoning_effort=#{inspect(Map.get(request, :reasoning))})"
    )

    request
  end
end
