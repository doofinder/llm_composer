defmodule LlmComposer.Cost.Fetchers.ModelsDev do
  @moduledoc """
  models.dev-specific pricing fetcher for OpenAI, Google, and Bedrock providers.

  Fetches pricing information from the models.dev API dataset for OpenAI, Google,
  and Amazon Bedrock models. Uses 24-hour caching to minimize API calls and improve
  performance.

  ## Supported Providers

  - `:open_ai` - OpenAI models (GPT series)
  - `:open_ai_responses` - OpenAI Responses API models (same pricing family as `:open_ai`)
  - `:google` - Google Gemini models
  - `:bedrock` - Amazon Bedrock models (indexed under `"amazon-bedrock"`)

  The optional third argument of `fetch_pricing/3` overrides the models.dev provider key,
  e.g. `"fireworks-ai"` for an OpenAI-compatible API used through `:open_ai`.

  ## Implementation Notes

  models.dev only exposes its pricing as a single consolidated dataset (api.json)
  covering every provider and model it tracks — there is no per-model endpoint
  to fetch instead. A caller only ever needs a handful of `{provider, model}`
  pairs, so caching the whole response would keep that entire dataset resident
  for the full TTL. Instead, each fetch resolves the pricing for the requested
  pair right after downloading and caches only that small result, keyed by
  `{provider_key, model}` — the full dataset itself is discarded once used and
  never cached. Two different models from the same provider each cost one
  extra full-document download (still bounded, since a given application only
  ever asks about a handful of models), trading a bit of network traffic for a
  cache footprint that scales with models actually used instead of models.dev's
  entire catalogue.

  See `LlmComposer.Cost.Fetchers.ModelsDev.Lookup` for the model-name fallback
  chain (region prefix, then date suffix) applied against the freshly fetched
  dataset on a cache miss.
  """

  alias LlmComposer.Cost.Fetchers.ModelsDev.Lookup
  alias LlmComposer.HttpClient
  alias LlmComposer.Providers.Utils

  require Logger

  @cache_mod Application.compile_env(:llm_composer, :cache_mod, LlmComposer.Cache.Ets)
  @models_dev_url "https://models.dev/"
  @default_cache_ttl_in_hours 24

  @spec fetch_pricing(atom(), String.t(), String.t() | nil) :: map() | nil
  def fetch_pricing(provider, model, models_dev_provider \\ nil)

  def fetch_pricing(provider, model, models_dev_provider)
      when provider in [:open_ai, :open_ai_responses, :google, :bedrock] do
    provider_key = models_dev_provider || provider_key(provider)
    cache_key = {provider_key, model}

    cache_key
    |> fetch_cost(provider_key, model)
    |> extract_pricing(provider_key, model)
  rescue
    e ->
      Logger.error(
        "Error fetching pricing from models.dev for provider=#{provider} model=#{model}: #{Exception.message(e)}"
      )

      nil
  end

  def fetch_pricing(_provider, _model, _models_dev_provider), do: nil

  defp fetch_cost(cache_key, provider_key, model) do
    case @cache_mod.get(cache_key) do
      {:ok, cost} ->
        Logger.debug("models.dev cache hit for #{provider_key}/#{model}")
        cost

      :miss ->
        Logger.debug("models.dev cache miss for #{provider_key}/#{model}")
        fetch_and_cache_cost(cache_key, provider_key, model)
    end
  end

  defp fetch_and_cache_cost(cache_key, provider_key, model) do
    case fetch_dataset() do
      {:ok, data} ->
        cost = Lookup.get_cost(data, provider_key, model)

        ttl =
          Application.get_env(:llm_composer, :cache_ttl, @default_cache_ttl_in_hours * 60 * 60)

        @cache_mod.put(cache_key, cost, ttl)
        cost

      :error ->
        nil
    end
  end

  defp fetch_dataset do
    client = HttpClient.client(base_url(), [])

    case Tesla.get(client, "/api.json") do
      {:ok, %{status: 200, body: data}} ->
        {:ok, data}

      {:ok, %{status: status}} ->
        Logger.warning("models.dev API returned status #{status}")
        :error

      {:error, reason} ->
        Logger.warning("Failed to fetch from models.dev API: #{inspect(reason)}")
        :error
    end
  end

  defp extract_pricing(%{"input" => input, "output" => output} = cost, provider_key, model) do
    Logger.debug(
      "Extracted pricing for #{provider_key}/#{model}: input=$#{input}/M, output=$#{output}/M"
    )

    pricing = %{
      input_price_per_million:
        input
        |> to_string()
        |> Decimal.new(),
      output_price_per_million:
        output
        |> to_string()
        |> Decimal.new()
    }

    case Map.get(cost, "cache_read") do
      nil ->
        pricing

      cache_read ->
        Map.put(
          pricing,
          :cache_read_price_per_million,
          cache_read
          |> to_string()
          |> Decimal.new()
        )
    end
  end

  defp extract_pricing(nil, provider_key, model) do
    Logger.debug("No pricing found for #{provider_key}/#{model} in models.dev data")
    nil
  end

  defp extract_pricing(invalid_cost, provider_key, model) do
    Logger.warning(
      "Invalid cost structure for #{provider_key}/#{model}: #{inspect(invalid_cost)}"
    )

    nil
  end

  @spec base_url() :: String.t()
  defp base_url, do: Utils.get_config(:models_dev, :base_url, [], @models_dev_url)

  defp provider_key(:open_ai), do: "openai"
  defp provider_key(:open_ai_responses), do: "openai"
  defp provider_key(:google), do: "google"
  defp provider_key(:bedrock), do: "amazon-bedrock"
end
