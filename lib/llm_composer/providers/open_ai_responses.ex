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
      |> Utils.get_tools(name())

    base_request = %{
      model: model,
      tools: tools,
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
    |> Enum.map(fn
      %{"role" => role, "content" => content} when is_binary(content) ->
        %{role: role, content: [%{type: "input_text", text: content}]}

      %{"role" => role, "content" => content} when is_list(content) ->
        %{role: role, content: content}

      other ->
        other
    end)
  end

  # Normalizes the Responses API body into the chat completions shape so the
  # existing `Parser.OpenAI` can handle it without changes.
  @spec normalize_body(map()) :: map()
  defp normalize_body(body) do
    text =
      case body["output_text"] do
        t when is_binary(t) and t != "" -> t
        _ -> extract_text_from_output(body["output"] || [])
      end

    usage = body["usage"] || %{}

    %{
      "model" => body["model"],
      "choices" => [
        %{"message" => %{"role" => "assistant", "content" => text}}
      ],
      "usage" => %{
        "prompt_tokens" => usage["input_tokens"] || 0,
        "completion_tokens" => usage["output_tokens"] || 0,
        "total_tokens" => usage["total_tokens"] || 0
      }
    }
  end

  @spec extract_text_from_output(list()) :: String.t()
  defp extract_text_from_output(output_items) do
    output_items
    |> Enum.flat_map(&Map.get(&1, "content", []))
    |> Enum.map_join("", &Map.get(&1, "text", ""))
  end

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
