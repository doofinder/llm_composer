if Code.ensure_loaded?(Decimal) do
  defmodule LlmComposer.Cost.Fetchers.ModelsDev do
    @moduledoc """
    models.dev-specific pricing fetcher for OpenAI and Google providers.

    Fetches pricing information from the models.dev API dataset for OpenAI and Google
    models. Uses 24-hour caching to minimize API calls and improve performance.

    ## Supported Providers

    - `:open_ai` - OpenAI models (GPT series)
    - `:google` - Google Gemini models

    ## Implementation Notes

    models.dev provides a single consolidated dataset (api.json) containing pricing
    for multiple providers. The entire dataset is cached to avoid repeated downloads.
    """

    alias LlmComposer.HttpClient

    require Logger

    @cache_mod Application.compile_env(:llm_composer, :cache_mod, LlmComposer.Cache.Ets)
    @models_dev_url "https://models.dev/"
    @cache_key "models_dev_api"
    @default_cache_ttl_in_hours 24

    @spec fetch_pricing(atom(), String.t()) :: map() | nil
    def fetch_pricing(provider, model) when provider in [:open_ai, :google] do
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
      provider_key =
        provider
        |> Atom.to_string()
        |> String.replace("_", "")

      case get_in(data, [provider_key, "models", model, "cost"]) do
        %{"input" => input, "output" => output} ->
          Logger.debug(
            "Extracted pricing for #{provider_key}/#{model}: input=$#{input}/M, output=$#{output}/M"
          )

          %{
            input_price_per_million:
              input
              |> to_string()
              |> Decimal.new(),
            output_price_per_million:
              output
              |> to_string()
              |> Decimal.new()
          }

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
  end
end
