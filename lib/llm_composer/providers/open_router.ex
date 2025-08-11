defmodule LlmComposer.Providers.OpenRouter do
  @moduledoc """
  Model implementation for OpenRouter

  OpenRouter API is very similar to Open AI API, but with some extras like model fallback.
  """
  @behaviour LlmComposer.Provider

  alias LlmComposer.Errors.MissingKeyError
  alias LlmComposer.HttpClient
  alias LlmComposer.LlmResponse
  alias LlmComposer.Providers.Utils

  require Logger

  @base_url Application.compile_env(
              :llm_composer,
              :open_router_url,
              "https://openrouter.ai/api/v1"
            )

  @impl LlmComposer.Provider
  def name, do: :open_router

  @impl LlmComposer.Provider
  @doc """
  Reference: https://openrouter.ai/docs/api-reference/chat-completion
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)
    api_key = Keyword.get(opts, :api_key) || get_key()
    client = HttpClient.client(@base_url, opts)

    headers = maybe_structured_output_headers([{"Authorization", "Bearer " <> api_key}], opts)
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

  defp build_request(messages, system_message, model, opts) do
    tools =
      opts
      |> Keyword.get(:functions)
      |> Utils.get_tools()

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
        track_costs(body)
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

  defp get_key do
    case Application.get_env(:llm_composer, :open_router_key) do
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

  defp maybe_structured_output_headers(headers, opts) do
    has_json_schema? =
      Keyword.has_key?(opts, :response_format) && opts[:response_format].type == "json_schema"

    if has_json_schema? do
      [{"Content-Type", "application/json"} | headers]
    else
      headers
    end
  end

  defp maybe_structured_output(base_request, opts) do
    response_format = Keyword.get(opts, :response_format)

    if response_format && is_map(response_format) do
      Map.put_new(base_request, :response_format, response_format)
    else
      base_request
    end
  end

  @spec track_costs(map()) :: map()
  defp track_costs(%{"model" => model, "provider" => provider, "usage" => usage}) do
    client = HttpClient.client(@base_url, [])

    {:ok, res} = Tesla.get(client, "/models/#{model}/endpoints")

    endpoints = get_in(res.body, ["data", "endpoints"])

    # sometimes provider has more than one endpoint (eg: google with vertex and vertex/global)
    endpoint = Enum.filter(endpoints, &(&1["provider_name"] == provider)) |> hd()

    cost = calculate_cost(usage, endpoint)

    Logger.debug("model=#{model} provider=#{provider} cost=#{Decimal.to_string(cost, :normal)}$")

    %{costs: cost}
  end

  @spec calculate_cost(map(), map()) :: Decimal.t()
  defp calculate_cost(
         %{"completion_tokens" => completion, "prompt_tokens" => prompt},
         %{"pricing" => %{"completion" => completion_costs, "prompt" => prompt_costs}}
       ) do
    completion_decimal = Decimal.new(completion_costs)
    prompt_decimal = Decimal.new(prompt_costs)

    completion_cost = Decimal.mult(completion_decimal, completion)
    prompt_cost = Decimal.mult(prompt_decimal, prompt)

    Decimal.add(completion_cost, prompt_cost)
  end
end
