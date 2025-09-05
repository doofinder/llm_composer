defmodule LlmComposer.Providers.OpenRouter do
  @moduledoc """
  Provider implementation for OpenRouter

  OpenRouter API is very similar to Open AI API, but with some extras like model fallback.
  """
  @behaviour LlmComposer.Provider

  alias LlmComposer.Errors.MissingKeyError
  alias LlmComposer.HttpClient
  alias LlmComposer.LlmResponse
  alias LlmComposer.Providers.OpenRouter.TrackCosts
  alias LlmComposer.Providers.Utils

  require Logger

  @impl LlmComposer.Provider
  def name, do: :open_router

  @impl LlmComposer.Provider
  @doc """
  Reference: https://openrouter.ai/docs/api-reference/chat-completion
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)
    api_key = get_key(opts)
    base_url = get_base_url(opts)
    client = HttpClient.client(base_url, opts)

    # headers = maybe_structured_output_headers([{"Authorization", "Bearer " <> api_key}], opts)
    headers = [{"Authorization", "Bearer " <> api_key}]
    req_opts = Utils.get_req_opts(opts)

    if model do
      messages
      |> build_request(system_message, model, opts)
      |> then(&Tesla.post(client, "/chat/completions", &1, headers: headers, opts: req_opts))
      |> handle_response(opts)
      |> LlmResponse.new(name())
    else
      {:error, :model_not_provided}
    end
  end

  # function required for costs tracking
  @spec get_base_url(keyword()) :: binary
  def get_base_url(opts \\ []),
    do: Utils.get_config(:open_router, :url, opts, "https://openrouter.ai/api/v1")

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
    |> Map.merge(req_params)
    |> maybe_fallback_models(opts)
    |> maybe_provider_routing(opts)
    |> maybe_structured_output(opts)
    |> Utils.cleanup_body()
  end

  @spec handle_response(Tesla.Env.result(), keyword()) :: {:ok, map()} | {:error, term}
  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}, completion_opts)
       when status in [200] do
    # if stream response, skip this logic for logging a warning
    if not is_function(body) and Keyword.get(completion_opts, :models) do
      original_model = Keyword.get(completion_opts, :model)
      used_model = body["model"]

      if original_model != used_model do
        Logger.warning("The '#{used_model}' model has been used instead of '#{original_model}'")
      end
    end

    metadata =
      if Keyword.get(completion_opts, :track_costs) and Code.ensure_loaded?(Decimal) do
        Logger.debug("retrieving cost of completion")
        TrackCosts.track_costs(body)
      else
        %{}
      end

    actions = Utils.extract_actions(body)
    {:ok, %{response: body, actions: actions, metadata: metadata}}
  end

  defp handle_response({:ok, resp}, _request_opts) do
    {:error, resp}
  end

  defp handle_response({:error, reason}, _request_opts) do
    {:error, reason}
  end

  defp get_key(opts) do
    case Utils.get_config(:open_router, :api_key, opts) do
      nil -> raise MissingKeyError
      key -> key
    end
  end

  defp maybe_fallback_models(base_request, opts) do
    fallback_models = Keyword.get(opts, :models)

    if fallback_models && is_list(fallback_models) do
      Map.put_new(base_request, :models, fallback_models)
    else
      base_request
    end
  end

  defp maybe_provider_routing(base_request, opts) do
    provider_routing = Keyword.get(opts, :provider_routing)

    if provider_routing && is_map(provider_routing) do
      Map.put_new(base_request, :provider, provider_routing)
    else
      base_request
    end
  end

  defp maybe_structured_output(base_request, opts) do
    response_format = Keyword.get(opts, :response_format)

    if response_format && is_map(response_format) do
      # Map.put_new(base_request, :response_format, response_format)
      Map.put_new(base_request, :response_format, %{
        "type" => "json_schema",
        "json_schema" => %{
          "name" => "response",
          "strict" => true,
          "schema" => response_format
        }
      })
    else
      base_request
    end
  end
end
