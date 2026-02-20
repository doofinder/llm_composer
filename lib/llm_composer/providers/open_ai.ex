defmodule LlmComposer.Providers.OpenAI do
  @moduledoc """
  Provider implementation for OpenAI

  Basically it calls the OpenAI api for getting the chat responses.
  """
  @behaviour LlmComposer.Provider

  alias LlmComposer.Errors.MissingKeyError
  alias LlmComposer.HttpClient
  alias LlmComposer.Providers.Utils
  alias LlmComposer.ProviderResponse.OpenAI, as: OpenAIResponse
  alias LlmComposer.ProviderResponse
  require Logger

  @impl LlmComposer.Provider
  def name, do: :open_ai

  @impl LlmComposer.Provider
  @doc """
  Reference: https://platform.openai.com/docs/api-reference/chat/create
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)
    api_key = get_key(opts)
    base_url = Utils.get_config(:open_ai, :url, opts, "https://api.openai.com/v1")
    client = HttpClient.client(base_url, opts)

    headers = [
      {"Authorization", "Bearer " <> api_key}
    ]

    req_opts = get_request_opts(opts)

    if model do
      endpoint = get_endpoint(model, opts)

      messages
      |> build_request(system_message, model, opts)
      |> maybe_convert_request_for_endpoint(endpoint)
      |> log_request_debug(model, endpoint)
      |> then(&Tesla.post(client, endpoint_path(endpoint), &1, headers: headers, opts: req_opts))
      |> handle_response(opts, endpoint)
      |> wrap_response(opts)
    else
      {:error, :model_not_provided}
    end
  end

  defp build_request(messages, system_message, model, opts) do
    tools =
      opts
      |> Keyword.get(:functions)
      |> Utils.get_tools(name())

    base_request = %{
      model: model,
      tools: tools,
      stream: Keyword.get(opts, :stream_response),
      messages: Utils.map_messages([system_message | messages])
    }

    req_params = Keyword.get(opts, :request_params, %{})

    base_request
    |> Utils.merge_request_params(req_params)
    |> maybe_structured_output(opts)
    |> Utils.cleanup_body()
  end

  @spec handle_response(Tesla.Env.result(), keyword(), :chat_completions | :responses) ::
          {:ok, map()} | {:error, term}
  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}, _opts, endpoint)
       when status in [200] do
    Logger.debug("[open_ai] successful response (endpoint=#{endpoint}, status=#{status})")

    case endpoint do
      :responses ->
        {:ok,
         %{
           response: normalize_responses_api_body(body),
           metadata: %{endpoint: endpoint, raw: body}
         }}

      :chat_completions ->
        {:ok, %{response: body, metadata: %{endpoint: endpoint}}}
    end
  end

  defp handle_response({:ok, resp}, _opts, endpoint) do
    Logger.warning(
      "[open_ai] non-200 response (endpoint=#{endpoint}, status=#{Map.get(resp, :status, :unknown)})"
    )

    {:error, resp}
  end

  defp handle_response({:error, reason}, _opts, endpoint) do
    Logger.error("[open_ai] request failed (endpoint=#{endpoint}, reason=#{inspect(reason)})")
    {:error, reason}
  end

  defp wrap_response(result, opts) do
    result
    |> OpenAIResponse.new(opts)
    |> ProviderResponse.to_llm_response(opts)
  end

  defp get_key(opts) do
    case Utils.get_config(:open_ai, :api_key, opts) do
      nil -> raise MissingKeyError
      key -> key
    end
  end

  defp maybe_structured_output(base_request, opts) do
    response_schema = Keyword.get(opts, :response_schema)

    if is_map(response_schema) do
      Map.put_new(base_request, :response_format, %{
        "type" => "json_schema",
        "json_schema" => %{
          "name" => "response",
          "strict" => true,
          "schema" => response_schema
        }
      })
    else
      base_request
    end
  end

  @spec get_endpoint(String.t(), keyword()) :: :chat_completions | :responses
  defp get_endpoint(model, opts) do
    case Keyword.get(opts, :open_ai_endpoint) do
      :chat_completions -> :chat_completions
      :responses -> :responses
      _ -> if String.starts_with?(model, "gpt-5"), do: :responses, else: :chat_completions
    end
  end

  @spec endpoint_path(:chat_completions | :responses) :: String.t()
  defp endpoint_path(:chat_completions), do: "/chat/completions"
  defp endpoint_path(:responses), do: "/responses"

  @spec maybe_convert_request_for_endpoint(map(), :chat_completions | :responses) :: map()
  defp maybe_convert_request_for_endpoint(request, :chat_completions), do: request
  defp maybe_convert_request_for_endpoint(request, :responses), do: to_responses_request(request)

  @spec to_responses_request(map()) :: map()
  defp to_responses_request(request) do
    {reasoning_effort, request} = pop_request_key(request, :reasoning_effort)

    messages = get_request_key(request, :messages, [])

    request
    |> Map.put(:input, map_messages_to_responses_input(messages))
    |> Map.delete(:messages)
    |> maybe_add_reasoning(reasoning_effort)
  end

  @spec map_messages_to_responses_input(list()) :: list()
  defp map_messages_to_responses_input(messages) do
    Enum.map(messages, fn
      %{"role" => role, "content" => content} when is_binary(content) ->
        %{
          role: role,
          content: [
            %{type: "input_text", text: content}
          ]
        }

      %{"role" => role, "content" => content} when is_list(content) ->
        %{role: role, content: content}

      other ->
        other
    end)
  end

  @spec maybe_add_reasoning(map(), String.t() | nil) :: map()
  defp maybe_add_reasoning(request, nil), do: request

  defp maybe_add_reasoning(request, effort) when is_binary(effort) do
    reasoning = get_request_key(request, :reasoning, %{})
    reasoning = Map.put(reasoning, :effort, effort)
    Map.put(request, :reasoning, reasoning)
  end

  @spec normalize_responses_api_body(map()) :: map()
  defp normalize_responses_api_body(body) do
    text =
      case body["output_text"] do
        text when is_binary(text) and text != "" -> text
        _ -> extract_text_from_responses_output(body["output"] || [])
      end

    usage = body["usage"] || %{}

    %{
      "model" => body["model"],
      "choices" => [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => text
          }
        }
      ],
      "usage" => %{
        "prompt_tokens" => usage["input_tokens"] || 0,
        "completion_tokens" => usage["output_tokens"] || 0,
        "total_tokens" => usage["total_tokens"] || 0
      }
    }
  end

  @spec extract_text_from_responses_output(list()) :: String.t()
  defp extract_text_from_responses_output(output_items) do
    output_items
    |> Enum.flat_map(fn item -> Map.get(item, "content", []) end)
    |> Enum.map(&Map.get(&1, "text", ""))
    |> Enum.join("")
  end

  @spec get_request_key(map(), atom(), term()) :: term()
  defp get_request_key(request, key, default) when is_atom(key) do
    Map.get(request, key, Map.get(request, Atom.to_string(key), default))
  end

  @spec pop_request_key(map(), atom()) :: {term(), map()}
  defp pop_request_key(request, key) when is_atom(key) do
    cond do
      Map.has_key?(request, key) -> Map.pop(request, key)
      Map.has_key?(request, Atom.to_string(key)) -> Map.pop(request, Atom.to_string(key))
      true -> {nil, request}
    end
  end

  @spec log_request_debug(map(), String.t(), :chat_completions | :responses) :: map()
  defp log_request_debug(request, model, endpoint) do
    timeout = Application.get_env(:llm_composer, :timeout, 50_000)

    Logger.debug(
      "[open_ai] sending request (model=#{model}, endpoint=#{endpoint}, stream=#{inspect(Map.get(request, :stream))}, timeout_ms=#{timeout})"
    )

    request
  end

  @spec get_request_opts(keyword()) :: keyword()
  defp get_request_opts(opts) do
    timeout = Keyword.get(opts, :timeout, Application.get_env(:llm_composer, :timeout, 50_000))

    adapter_opts = [receive_timeout: timeout]

    opts
    |> Utils.get_req_opts()
    |> Keyword.update(:adapter, adapter_opts, &Keyword.merge(&1, adapter_opts))
  end
end
