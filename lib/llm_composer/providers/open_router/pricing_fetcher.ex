defmodule LlmComposer.Providers.OpenRouter.PricingFetcher do
  @moduledoc false

  import LlmComposer.Providers.OpenRouter, only: [get_base_url: 0]

  alias LlmComposer.HttpClient

  require Logger

  @cache_mod Application.compile_env(:llm_composer, :cache_mod, LlmComposer.Cache.Ets)

  @spec fetch_pricing(map()) :: map() | nil
  def fetch_pricing(%{"model" => model, "provider" => provider, "usage" => usage}) do
    endpoint = get_endpoint_data(model, provider)

    if is_nil(endpoint) do
      Logger.warning("No endpoint found for model=#{model} provider=#{provider}")
      nil
    else
      pricing = endpoint["pricing"]

      if is_nil(pricing) or not is_map(pricing) do
        Logger.warning("Invalid pricing data for model=#{model} provider=#{provider}")
        nil
      else
        completion_per_token = Decimal.new(pricing["completion"])
        prompt_per_token = Decimal.new(pricing["prompt"])

        input_price_per_million = Decimal.mult(prompt_per_token, Decimal.new(1_000_000))
        output_price_per_million = Decimal.mult(completion_per_token, Decimal.new(1_000_000))

        cost = calculate_cost(usage, endpoint)

        Logger.debug(
          "model=#{model} provider=#{provider} cost=#{Decimal.to_string(cost, :normal)}$"
        )

        %{
          input_price_per_million: input_price_per_million,
          output_price_per_million: output_price_per_million,
          total_cost: cost
        }
      end
    end
  rescue
    e ->
      Logger.error(
        "Error fetching pricing for model=#{model} provider=#{provider}: #{Exception.message(e)}"
      )

      nil
  end

  @spec calculate_cost(map(), map()) :: Decimal.t()
  defp calculate_cost(
         %{"completion_tokens" => completion, "prompt_tokens" => prompt},
         %{"pricing" => %{"completion" => completion_costs, "prompt" => prompt_costs}}
       ) do
    completion_decimal = Decimal.new(completion_costs)
    prompt_decimal = Decimal.new(prompt_costs)

    completion_cost = Decimal.mult(completion_decimal, Decimal.new(to_string(completion)))
    prompt_cost = Decimal.mult(prompt_decimal, Decimal.new(to_string(prompt)))

    Decimal.add(completion_cost, prompt_cost)
  end

  @spec get_endpoint_data(binary, binary) :: map() | nil
  defp get_endpoint_data(model, provider) do
    case fetch_model_endpoints_with_cache(model, provider, get_base_url()) do
      nil ->
        nil

      model_endpoints ->
        model_endpoints
        |> get_in(["data", "endpoints"])
        |> get_endpoint(provider)
    end
  end

  @spec fetch_model_endpoints_with_cache(binary, binary, binary) :: map() | nil
  defp fetch_model_endpoints_with_cache(model, provider, base_url) do
    key = model

    case @cache_mod.get(key) do
      {:ok, resp} -> handle_cache_hit(resp, key, model, provider, base_url)
      :miss -> handle_cache_miss(key, model, base_url)
    end
  end

  defp handle_cache_hit(resp, key, model, provider, base_url) do
    Logger.debug("cache hit")

    if is_nil(get_endpoint(resp["data"]["endpoints"], provider)) do
      @cache_mod.delete(key)
      # Retry only once
      fetch_model_endpoints_with_cache(model, provider, base_url)
    else
      resp
    end
  end

  defp handle_cache_miss(key, model, base_url) do
    Logger.debug("cache miss")

    with client <- HttpClient.client(base_url, []),
         {:ok, endpoints_response} <- Tesla.get(client, "/models/#{model}/endpoints") do
      # 24h ttl default
      ttl = Application.get_env(:llm_composer, :cache_ttl, 60 * 60 * 24)
      @cache_mod.put(key, endpoints_response.body, ttl)
      endpoints_response.body
    else
      {:error, reason} ->
        Logger.warning("Failed to fetch endpoints for model=#{model}: #{inspect(reason)}")
        nil
    end
  end

  @spec get_endpoint(list(map()), binary) :: map() | nil
  defp get_endpoint(endpoints, provider) do
    endpoints
    |> Enum.filter(&(&1["provider_name"] == provider))
    |> then(fn
      [endpoint | _tail] -> endpoint
      [] -> nil
    end)
  end
end
