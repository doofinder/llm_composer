defmodule LlmComposer.Cost.Pricing do
  @moduledoc """
  Centralized pricing retrieval and calculation module (moved under cost/).

  Supports multiple pricing sources with caching:
  - Explicit provider options
  - OpenRouter API
  - models.dev API (OpenAI/Google only)
  """

  alias LlmComposer.Cost.OpenRouterPricingFetcher
  alias LlmComposer.HttpClient

  require Logger

  @cache_mod Application.compile_env(:llm_composer, :cache_mod, LlmComposer.Cache.Ets)

  @spec fetch_pricing(atom(), keyword()) :: keyword() | nil
  def fetch_pricing(provider, opts) do
    # Priority chain: explicit opts -> provider-specific API
    if explicit_pricing?(opts) do
      extract_explicit_pricing(opts)
    else
      case provider do
        :open_router -> fetch_openrouter_pricing(opts)
        provider when provider in [:open_ai, :google] -> fetch_models_dev_pricing(provider, opts)
        _ -> nil
      end
    end
  end

  @spec calculate_cost(Decimal.t() | nil, non_neg_integer() | nil, Decimal.t() | nil) ::
          Decimal.t() | nil
  def calculate_cost(%Decimal{} = existing_cost, _tokens, _price), do: existing_cost

  def calculate_cost(_existing_cost, _tokens, nil), do: nil

  def calculate_cost(_existing_cost, nil, _price), do: nil

  def calculate_cost(nil, tokens, price) do
    tokens
    |> Decimal.new()
    |> Decimal.div(Decimal.new(1_000_000))
    |> Decimal.mult(price)
  end

  # Check if explicit pricing is provided in opts
  defp explicit_pricing?(opts) do
    not is_nil(opts[:input_price_per_million]) and not is_nil(opts[:output_price_per_million])
  end

  # Extract explicit pricing from opts
  defp extract_explicit_pricing(opts) do
    [
      input_price_per_million: Decimal.new(opts[:input_price_per_million]),
      output_price_per_million: Decimal.new(opts[:output_price_per_million]),
      currency: "USD"
    ]
  end

  # Fetch pricing from OpenRouter API
  defp fetch_openrouter_pricing(opts) do
    body = Keyword.get(opts, :body)

    if is_nil(body) do
      nil
    else
      case OpenRouterPricingFetcher.fetch_pricing(body) do
        %{input_price_per_million: input_price, output_price_per_million: output_price} ->
          [
            input_price_per_million: input_price,
            output_price_per_million: output_price,
            currency: "USD"
          ]

        _ ->
          nil
      end
    end
  end

  # Fetch pricing from models.dev API for OpenAI/Google providers
  @spec fetch_models_dev_pricing(atom(), keyword()) :: keyword() | nil
  def fetch_models_dev_pricing(provider, opts) when provider in [:open_ai, :google] do
    model = Keyword.get(opts, :model)

    if is_nil(model) do
      Logger.warning("No model specified for models.dev pricing fetch")
      nil
    else
      case models_dev_fetcher(provider, model) do
        %{input_price_per_million: input, output_price_per_million: output} ->
          [
            input_price_per_million: input,
            output_price_per_million: output,
            currency: "USD"
          ]

        nil ->
          nil
      end
    end
  end

  def fetch_models_dev_pricing(_provider, _opts), do: nil

  @spec models_dev_fetcher(atom(), String.t()) :: map() | nil
  def models_dev_fetcher(provider, model) when provider in [:open_ai, :google] do
    cache_key = "models_dev_api"

    case @cache_mod.get(cache_key) do
      {:ok, cached_data} ->
        Logger.debug("models.dev cache hit")
        extract_pricing_from_data(cached_data, provider, model)

      :miss ->
        Logger.debug("models.dev cache miss")
        fetch_and_cache_models_dev_data(cache_key, provider, model)
    end
  rescue
    e ->
      Logger.error(
        "Error fetching pricing from models.dev for provider=#{provider} model=#{model}: #{Exception.message(e)}"
      )

      nil
  end

  def models_dev_fetcher(_provider, _model), do: nil

  @spec fetch_and_cache_models_dev_data(term(), atom(), binary()) :: map() | nil
  defp fetch_and_cache_models_dev_data(cache_key, provider, model) do
    client = HttpClient.client("https://models.dev/", [])

    case Tesla.get(client, "/api.json") do
      {:ok, %{status: 200, body: data}} ->
        # Cache for 24 hours
        ttl = Application.get_env(:llm_composer, :cache_ttl, 60 * 60 * 24)
        @cache_mod.put(cache_key, data, ttl)
        extract_pricing_from_data(data, provider, model)

      {:ok, %{status: status}} ->
        Logger.warning("models.dev API returned status #{status}")
        nil

      {:error, reason} ->
        Logger.warning("Failed to fetch from models.dev API: #{inspect(reason)}")
        nil
    end
  end

  @spec extract_pricing_from_data(map(), atom(), String.t()) :: map() | nil
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
