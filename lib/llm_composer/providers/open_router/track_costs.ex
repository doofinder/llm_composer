defmodule LlmComposer.Providers.OpenRouter.TrackCosts do
  @moduledoc false

  import LlmComposer.Providers.OpenRouter, only: [get_base_url: 0]

  alias LlmComposer.HttpClient

  require Logger

  @cache_mod Application.compile_env(:llm_composer, :cache_mod, LlmComposer.Cache.Ets)

  @spec track_costs(map()) :: map()
  def track_costs(%{"model" => model, "provider" => provider, "usage" => usage}) do
    {:ok, res} = fetch_model_endpoints_with_cache(model, get_base_url())

    endpoints = get_in(res.body, ["data", "endpoints"])

    # sometimes provider has more than one endpoint (eg: google with vertex and vertex/global)
    endpoint =
      endpoints
      |> Enum.filter(&(&1["provider_name"] == provider))
      |> hd()

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

  @spec fetch_model_endpoints_with_cache(binary, binary) :: {:ok, map()}
  defp fetch_model_endpoints_with_cache(model, base_url) do
    case @cache_mod.get(model) do
      :miss ->
        Logger.debug("cache miss")
        client = HttpClient.client(base_url, [])
        resp = Tesla.get(client, "/models/#{model}/endpoints")

        # 24h ttl
        @cache_mod.put(model, resp, 60 * 60 * 24)

        resp

      {:ok, resp} ->
        Logger.debug("cache hit")
        resp
    end
  end
end
