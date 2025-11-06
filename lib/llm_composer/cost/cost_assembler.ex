if Code.ensure_loaded?(Decimal) do
  defmodule LlmComposer.Cost.CostAssembler do
    @moduledoc """
    Centralized cost information assembly module.

    Handles the extraction of cost-related data from provider responses and
    assembles `CostInfo` structs. This module consolidates all cost logic that
    was previously scattered across the response handler.

    ## Responsibilities

    - Extract tokens from provider-specific response formats
    - Resolve model names (from response or options)
    - Prepare pricing options for cost calculation
    - Assemble complete CostInfo structs

    ## Provider-Specific Handling

    - **OpenAI/OpenRouter**: Extracts tokens from `usage` field, model from response
    - **Google**: Extracts tokens from `usageMetadata` field, model from options
    """

    alias LlmComposer.Cost.Pricing
    alias LlmComposer.CostInfo

    require Logger

    @spec get_cost_info(
            provider :: atom(),
            raw_response :: map(),
            opts :: keyword()
          ) :: CostInfo.t() | nil
    def get_cost_info(provider, raw_response, opts) do
      if Keyword.get(opts, :track_costs) do
        {input_tokens, output_tokens} = extract_tokens(provider, raw_response)
        model = get_model(provider, raw_response, opts)

        pricing_opts_prepared = prepare_pricing_opts(provider, raw_response, opts)
        pricing_opts = Pricing.fetch_pricing(provider, pricing_opts_prepared)

        Logger.debug(
          "Assembling cost info for #{provider}: model=#{model}, input=#{input_tokens}, output=#{output_tokens}"
        )

        CostInfo.new(
          provider,
          model,
          input_tokens,
          output_tokens,
          pricing_opts || []
        )
      else
        nil
      end
    end

    @spec extract_tokens(atom(), map()) :: {non_neg_integer(), non_neg_integer()}
    def extract_tokens(provider, raw_response) when provider in [:open_ai, :open_router] do
      input = get_in(raw_response, ["usage", "prompt_tokens"]) || 0
      output = get_in(raw_response, ["usage", "completion_tokens"]) || 0
      {input, output}
    end

    def extract_tokens(:google, raw_response) do
      usage = raw_response["usageMetadata"] || %{}
      input = usage["promptTokenCount"] || 0
      output = usage["candidatesTokenCount"] || 0
      {input, output}
    end

    def extract_tokens(_provider, _raw_response) do
      {0, 0}
    end

    @spec get_model(atom(), map(), keyword()) :: String.t() | nil
    defp get_model(provider, raw_response, _opts) when provider in [:open_ai, :open_router] do
      get_in(raw_response, ["model"])
    end

    defp get_model(:google, _raw_response, opts) do
      Keyword.get(opts, :model)
    end

    defp get_model(_provider, _raw_response, _opts) do
      nil
    end

    @spec prepare_pricing_opts(atom(), map(), keyword()) :: keyword()
    defp prepare_pricing_opts(:open_router, %{"model" => _model} = raw_response, opts) do
      provider = Map.get(raw_response, "provider", "openrouter")
      body = Map.put(raw_response, "provider", provider)
      Keyword.put(opts, :body, body)
    end

    defp prepare_pricing_opts(:google, _raw_response, opts) do
      opts
    end

    defp prepare_pricing_opts(_provider, _raw_response, opts) do
      opts
    end
  end
end
