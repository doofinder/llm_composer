defmodule LlmComposer.Providers.OpenAI do
  @moduledoc """
  Provider implementation for OpenAI chat completions API.

  Reference: https://platform.openai.com/docs/api-reference/chat/create
  """
  @behaviour LlmComposer.Provider

  alias LlmComposer.HttpClient
  alias LlmComposer.ProviderResponse
  alias LlmComposer.Providers.Utils

  require Logger

  @impl LlmComposer.Provider
  def name, do: :open_ai

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
      |> then(&Tesla.post(client, "/chat/completions", &1, headers: headers, opts: req_opts))
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
      stream: Keyword.get(opts, :stream_response),
      messages: Utils.map_messages([system_message | messages])
    }

    req_params = Keyword.get(opts, :request_params, %{})

    base_request
    |> Utils.merge_request_params(req_params)
    |> maybe_structured_output(opts)
    |> Utils.cleanup_body()
  end

  @spec handle_response(Tesla.Env.result()) :: {:ok, map()} | {:error, term()}
  defp handle_response({:ok, %Tesla.Env{status: 200, body: body}}) do
    Logger.debug("[open_ai] successful response")
    {:ok, %{response: body}}
  end

  defp handle_response({:ok, resp}) do
    Logger.warning("[open_ai] non-200 response (status=#{Map.get(resp, :status, :unknown)})")
    {:error, resp}
  end

  defp handle_response({:error, reason}) do
    Logger.error("[open_ai] request failed (reason=#{inspect(reason)})")
    {:error, reason}
  end

  @spec wrap_response({:ok, map()} | {:error, term()}, keyword()) ::
          {:ok, LlmComposer.LlmResponse.t()} | {:error, term()}
  defp wrap_response(result, opts) do
    result
    |> ProviderResponse.OpenAI.new(opts)
    |> ProviderResponse.to_llm_response(opts)
  end

  @spec maybe_structured_output(map(), keyword()) :: map()
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

  @spec log_request_debug(map(), String.t()) :: map()
  defp log_request_debug(request, model) do
    timeout = Application.get_env(:llm_composer, :timeout, 50_000)

    Logger.debug(
      "[open_ai] sending request (model=#{model}, stream=#{inspect(Map.get(request, :stream))}, timeout_ms=#{timeout})"
    )

    request
  end
end
