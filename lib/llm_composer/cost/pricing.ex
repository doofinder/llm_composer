if Code.ensure_loaded?(Decimal) do
  defmodule LlmComposer.Cost.Pricing do
    @moduledoc """
    Centralized pricing retrieval and calculation module.

    Orchestrates pricing retrieval from multiple sources with priority chain:
    1. Explicit pricing from provider options (input_price_per_million, output_price_per_million)
    2. Provider-specific APIs:
      - OpenRouter API for :open_router provider
      - models.dev API for :open_ai and :google providers
    3. Fallback to nil if no pricing source available

    """

    alias LlmComposer.Cost.Fetchers.ModelsDev
    alias LlmComposer.Cost.Fetchers.OpenRouter

    require Logger

    @spec fetch_pricing(atom(), keyword()) :: keyword() | nil
    def fetch_pricing(provider, opts) do
      # Priority chain: explicit opts -> provider-specific API
      if explicit_pricing?(opts) do
        extract_explicit_pricing(opts)
      else
        case provider do
          :open_router ->
            fetch_openrouter_pricing(opts)

          provider when provider in [:open_ai, :google] ->
            fetch_models_dev_pricing(provider, opts)

          _ ->
            nil
        end
      end
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

    defp fetch_openrouter_pricing(opts) do
      body = Keyword.get(opts, :body)

      if is_nil(body) do
        nil
      else
        transform_fetcher_response(OpenRouter.fetch_pricing(body))
      end
    end

    defp fetch_models_dev_pricing(provider, opts) when provider in [:open_ai, :google] do
      model = Keyword.get(opts, :model)

      if is_nil(model) do
        Logger.warning("No model specified for models.dev pricing fetch")
        nil
      else
        transform_fetcher_response(ModelsDev.fetch_pricing(provider, model))
      end
    end

    defp transform_fetcher_response(%{
           input_price_per_million: input,
           output_price_per_million: output
         }) do
      [
        input_price_per_million: input,
        output_price_per_million: output,
        currency: "USD"
      ]
    end

    defp transform_fetcher_response(nil), do: nil
  end
end
