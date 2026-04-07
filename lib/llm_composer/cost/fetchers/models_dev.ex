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

  ## Implementation Notes

  models.dev provides a single consolidated dataset (api.json) containing pricing
  for multiple providers. The entire dataset is cached to avoid repeated downloads.

  For Bedrock, model lookup uses the following fallback chain:
  1. Exact model name (some region-prefixed variants are indexed, e.g. `"eu.anthropic.claude-sonnet-4-6"`)
  2. Region prefix stripped (e.g. `"eu.amazon.nova-lite-v1:0"` → `"amazon.nova-lite-v1:0"`)
  3. Date suffix stripped (e.g. `"amazon.nova-lite-v1:0-2026-01-01"` → `"amazon.nova-lite-v1:0"`)
  """

  alias LlmComposer.HttpClient

  require Logger

  @cache_mod Application.compile_env(:llm_composer, :cache_mod, LlmComposer.Cache.Ets)
  @models_dev_url "https://models.dev/"
  @cache_key "models_dev_api"
  @default_cache_ttl_in_hours 24

  @spec fetch_pricing(atom(), String.t()) :: map() | nil
  def fetch_pricing(provider, model)
      when provider in [:open_ai, :open_ai_responses, :google, :bedrock] do
    case fetch_with_cache() do
      {:ok, data} -> extract_pricing_from_data(data, provider, model)
      :error -> nil
    end
  rescue
    e ->
      Logger.error(
        "Error fetching pricing from models.dev for provider=#{provider} model=#{model}: #{Exception.message(e)}"
      )

      nil
  end

  def fetch_pricing(_provider, _model), do: nil

  defp fetch_with_cache do
    case @cache_mod.get(@cache_key) do
      {:ok, cached_data} ->
        Logger.debug("models.dev cache hit")
        {:ok, cached_data}

      :miss ->
        Logger.debug("models.dev cache miss")
        fetch_and_cache_data()
    end
  end

  defp fetch_and_cache_data do
    client = HttpClient.client(@models_dev_url, [])

    case Tesla.get(client, "/api.json") do
      {:ok, %{status: 200, body: data}} ->
        ttl =
          Application.get_env(:llm_composer, :cache_ttl, @default_cache_ttl_in_hours * 60 * 60)

        @cache_mod.put(@cache_key, data, ttl)
        {:ok, data}

      {:ok, %{status: status}} ->
        Logger.warning("models.dev API returned status #{status}")
        :error

      {:error, reason} ->
        Logger.warning("Failed to fetch from models.dev API: #{inspect(reason)}")
        :error
    end
  end

  defp extract_pricing_from_data(data, provider, model) do
    provider_key = provider_key(provider)

    case get_cost(data, provider_key, model) do
      %{"input" => input, "output" => output} = cost ->
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

      nil ->
        Logger.debug("No pricing found for #{provider_key}/#{model} in models.dev data")
        nil

      invalid_cost ->
        Logger.warning(
          "Invalid cost structure for #{provider_key}/#{model}: #{inspect(invalid_cost)}"
        )

        nil
    end
  end

  defp get_cost(data, provider_key, model) do
    case get_in(data, [provider_key, "models", model, "cost"]) do
      nil -> fallback_strip_region(data, provider_key, model)
      cost -> cost
    end
  end

  # Some Bedrock models have region prefixes (eu., us., ap., global.) that are not
  # indexed in models.dev. Strip the prefix and retry before falling back further.
  defp fallback_strip_region(data, provider_key, model) do
    case strip_region_prefix(model) do
      ^model ->
        fallback_strip_date(data, provider_key, model)

      stripped_model ->
        Logger.debug(
          "Retrying models.dev pricing lookup for #{provider_key}/#{model} without region prefix (#{stripped_model})"
        )

        case get_in(data, [provider_key, "models", stripped_model, "cost"]) do
          nil -> fallback_strip_date(data, provider_key, stripped_model)
          cost -> cost
        end
    end
  end

  # APIs like OpenAI return snapshot model names with a date suffix (e.g. "gpt-5.4-mini-2026-03-17"),
  # but models.dev only indexes the base name. Strip the suffix and retry.
  defp fallback_strip_date(data, provider_key, model) do
    case strip_snapshot_date_suffix(model) do
      ^model ->
        nil

      fallback_model ->
        Logger.debug(
          "Retrying models.dev pricing lookup for #{provider_key}/#{model} with fallback #{fallback_model}"
        )

        get_in(data, [provider_key, "models", fallback_model, "cost"])
    end
  end

  @region_prefix_regex ~r/^(?:eu|us|ap|global)\./

  defp strip_region_prefix(model) when is_binary(model) do
    Regex.replace(@region_prefix_regex, model, "")
  end

  defp strip_snapshot_date_suffix(model) when is_binary(model) do
    Regex.replace(~r/-\d{4}-\d{2}-\d{2}$/, model, "")
  end

  defp provider_key(:open_ai), do: "openai"
  defp provider_key(:open_ai_responses), do: "openai"
  defp provider_key(:google), do: "google"
  defp provider_key(:bedrock), do: "amazon-bedrock"
end
