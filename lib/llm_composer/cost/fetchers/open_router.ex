defmodule LlmComposer.Cost.Fetchers.OpenRouter do
  @moduledoc """
  OpenRouter-specific pricing fetcher.

  Fetches pricing information from OpenRouter's models API for the specified model
  and provider combination. Uses 24-hour caching to minimize API calls.

  ## Implementation Notes

  OpenRouter's pricing API requires both model and provider parameters because
  the same model can be served by different providers with different pricing.
  """

  import LlmComposer.Providers.OpenRouter, only: [get_base_url: 0]

  alias LlmComposer.HttpClient

  require Logger

  @cache_mod Application.compile_env(:llm_composer, :cache_mod, LlmComposer.Cache.Ets)
  @default_cache_ttl_in_hours 24

  @spec fetch_pricing(map()) :: map() | nil
  def fetch_pricing(%{"model" => model, "provider" => provider} = _body) do
    with {:ok, endpoint} <- validate_endpoint(model, provider),
         {:ok, pricing} <- validate_pricing(endpoint, model, provider) do
      build_pricing_result(pricing, model, provider)
    else
      {:error, _reason} -> nil
    end
  rescue
    e ->
      Logger.error(
        "Error fetching pricing for model=#{inspect(model)} provider=#{inspect(provider)}: #{Exception.message(e)}"
      )

      nil
  end

  defp validate_endpoint(model, provider) do
    case get_endpoint_data(model, provider) do
      nil ->
        Logger.warning("No endpoint found for model=#{model} provider=#{provider}")
        {:error, :no_endpoint}

      endpoint ->
        {:ok, endpoint}
    end
  end

  defp validate_pricing(%{"pricing" => pricing}, _model, _provider) when is_map(pricing) do
    {:ok, pricing}
  end

  defp validate_pricing(_endpoint, model, provider) do
    Logger.warning("Invalid pricing data for model=#{model} provider=#{provider}")
    {:error, :invalid_pricing}
  end

  defp build_pricing_result(pricing, model, provider) do
    completion_per_token = Decimal.new(pricing["completion"])
    prompt_per_token = Decimal.new(pricing["prompt"])

    input_price_per_million = Decimal.mult(prompt_per_token, Decimal.new(1_000_000))
    output_price_per_million = Decimal.mult(completion_per_token, Decimal.new(1_000_000))

    Logger.debug(
      "model=#{model} provider=#{provider} input_price=$#{Decimal.to_string(input_price_per_million, :normal)}/M output_price=$#{Decimal.to_string(output_price_per_million, :normal)}/M"
    )

    %{
      input_price_per_million: input_price_per_million,
      output_price_per_million: output_price_per_million
    }
  end

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
      ttl = Application.get_env(:llm_composer, :cache_ttl, @default_cache_ttl_in_hours * 60 * 60)
      @cache_mod.put(key, endpoints_response.body, ttl)
      endpoints_response.body
    else
      {:error, reason} ->
        Logger.warning("Failed to fetch endpoints for model=#{model}: #{inspect(reason)}")
        nil
    end
  end

  defp get_endpoint(endpoints, provider) do
    endpoints
    |> Enum.filter(&(&1["provider_name"] == provider))
    |> then(fn
      [endpoint | _tail] -> endpoint
      [] -> nil
    end)
  end
end
