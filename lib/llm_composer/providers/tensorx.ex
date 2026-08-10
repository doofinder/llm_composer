defmodule LlmComposer.Providers.TensorX do
  @moduledoc """
  Provider implementation for TensorX (https://tensorx.ai).

  TensorX serves an OpenAI-compatible Chat Completions API from EU-only
  infrastructure, which makes it a drop-in alternative to OpenRouter when
  inference must stay in Europe.

  ## Location

  There is no per-request region parameter: TensorX runs a single EU-hosted
  endpoint (`https://api.tensorx.ai/v1`), so "location: Europe" is a property of
  the base URL. `get_base_url/1` returns that endpoint by default; override
  `:url` only for tests or proxies.

  ## Differences with `LlmComposer.Providers.OpenRouter`

  - no fallback `:models` list and no `:provider_routing` — there is a single
    upstream, so `LlmComposer.ProvidersRunner` is the way to fail over,
  - reasoning text arrives in `reasoning_content` (handled by the shared OpenAI
    parser), and the thinking switches are per model family, passed through
    `request_params` (e.g. `%{chat_template_kwargs: %{thinking: false}}` for
    DeepSeek V4, `%{chat_template_kwargs: %{enable_thinking: false}}` for GLM),
  - TensorX publishes no machine-readable price feed, so cost tracking needs
    explicit `:input_price_per_million` / `:output_price_per_million` (and
    optionally `:cache_read_price_per_million`) provider options.
  """
  @behaviour LlmComposer.Provider

  alias LlmComposer.Errors.MissingKeyError
  alias LlmComposer.HttpClient
  alias LlmComposer.ProviderResponse
  alias LlmComposer.Providers.Utils

  @impl LlmComposer.Provider
  def name, do: :tensorx

  @impl LlmComposer.Provider
  @doc """
  Reference: https://docs.tensorx.ai/api-reference/chat-completions
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)

    if model do
      api_key = get_key(opts)
      base_url = get_base_url(opts)
      client = HttpClient.client(base_url, opts)
      headers = [{"Authorization", "Bearer " <> api_key} | Keyword.get(opts, :headers, [])]
      req_opts = Utils.get_req_opts(opts)

      messages
      |> build_request(system_message, model, opts)
      |> then(&Tesla.post(client, "/chat/completions", &1, headers: headers, opts: req_opts))
      |> handle_response()
      |> wrap_response(opts)
    else
      {:error, :model_not_provided}
    end
  end

  @doc """
  Base URL of the TensorX API, EU-hosted by default.
  """
  @spec get_base_url(keyword()) :: binary
  def get_base_url(opts \\ []),
    do: Utils.get_config(:tensorx, :url, opts, "https://api.tensorx.ai/v1")

  defp build_request(messages, system_message, model, opts) do
    tools =
      opts
      |> Keyword.get(:functions)
      |> Utils.get_tools(name())

    base_request = %{
      model: model,
      tools: tools,
      stream: Keyword.get(opts, :stream_response),
      messages: Utils.map_messages([system_message | messages], name())
    }

    req_params = Keyword.get(opts, :request_params, %{})

    base_request
    |> Utils.merge_request_params(req_params)
    |> maybe_structured_output(opts)
    |> Utils.cleanup_body()
  end

  @spec handle_response(Tesla.Env.result()) :: {:ok, map()} | {:error, term}
  defp handle_response({:ok, %Tesla.Env{status: 200, body: body}}), do: {:ok, %{response: body}}
  defp handle_response({:ok, resp}), do: {:error, resp}
  defp handle_response({:error, reason}), do: {:error, reason}

  defp wrap_response(result, opts) do
    result
    |> ProviderResponse.TensorX.new(opts)
    |> ProviderResponse.to_llm_response(opts)
  end

  defp get_key(opts) do
    case Utils.get_config(:tensorx, :api_key, opts) do
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
end
