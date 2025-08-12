defmodule LlmComposer.Providers.OpenRouter.TrackCosts do
  @moduledoc false

  import LlmComposer.Providers.OpenRouter, only: [get_base_url: 0]

  alias LlmComposer.HttpClient

  require Logger

  @cache_mod Application.compile_env(:llm_composer, :cache_mod, LlmComposer.Cache.Ets)

  @spec track_costs(map()) :: map()
  def track_costs(%{"model" => model, "provider" => provider, "usage" => usage}) do
    endpoint = get_endpoint_data(model, provider)

    cost = calculate_cost(usage, endpoint)

    Logger.debug("model=#{model} provider=#{provider} cost=#{Decimal.to_string(cost, :normal)}$")

    %{total_cost: cost}
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

  @spec get_endpoint_data(binary, binary) :: map()
  defp get_endpoint_data(model, provider) do
    model_endpoints = fetch_model_endpoints_with_cache(model, provider, get_base_url())

    model_endpoints
    |> get_in(["data", "endpoints"])
    |> get_endpoint(provider)
  end

  @spec fetch_model_endpoints_with_cache(binary, binary, binary) :: map()
  defp fetch_model_endpoints_with_cache(model, provider, base_url) do
    key = model

    # here we cache the response, and if data in cache, we check that the provider exists, if not we invalidate to retry.
    case @cache_mod.get(key) do
      {:ok, resp} ->
        Logger.debug("cache hit")

        if is_nil(get_endpoint(resp["data"]["endpoints"], provider)) do
          @cache_mod.delete(key)

          # retry if provider not found in cache... it should retry just once as non cache case has no retry.
          fetch_model_endpoints_with_cache(model, provider, base_url)
        else
          resp
        end

      :miss ->
        Logger.debug("cache miss")

        with client <- HttpClient.client(base_url, []),
             {:ok, endpoints_response} <- Tesla.get(client, "/models/#{model}/endpoints") do
          # 24h ttl default
          ttl = Application.get_env(:llm_composer, :cache_ttl, 60 * 60 * 24)
          @cache_mod.put(key, endpoints_response.body, ttl)
          endpoints_response.body
        end
    end
  end

  @spec get_endpoint(list(map()), binary) :: map() | nil
  defp get_endpoint(endpoints, provider) do
    endpoints
    |> Enum.filter(&(&1["provider_name"] == provider))
    |> then(fn
      [endpoint | _] -> endpoint
      [] -> nil
    end)
  end
end
