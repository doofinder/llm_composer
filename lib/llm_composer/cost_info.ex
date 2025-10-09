defmodule LlmComposer.CostInfo do
  @moduledoc """
  Struct for tracking costs and token usage of LLM API calls.

  This module provides a standardized way to track both token usage and financial costs
  across different LLM providers. It supports both streaming and non-streaming responses
  and can automatically calculate costs when provided with pricing information.

  ## Pricing Requirements

  When providing pricing information, both `input_price_per_million` and `output_price_per_million`
  must be provided together. Providing only one will raise an `ArgumentError`.

  ## Fields

  * `:input_tokens` - Number of tokens in the input/prompt
  * `:output_tokens` - Number of tokens in the output/completion
  * `:total_tokens` - Total tokens used (input + output)
  * `:input_cost` - Cost for input tokens (using Decimal for precision)
  * `:output_cost` - Cost for output tokens (using Decimal for precision)
  * `:total_cost` - Total cost for the request (using Decimal for precision)
  * `:currency` - Currency code (e.g., "USD", "EUR")
  * `:provider_model` - The actual model used by the provider
  * `:provider_name` - The provider that served the request
  * `:input_price_per_million` - Price per million input tokens
  * `:output_price_per_million` - Price per million output tokens
  * `:metadata` - Additional provider-specific cost information

  ## Examples

    # Basic token tracking
    %LlmComposer.CostInfo{
      input_tokens: 150,
      output_tokens: 75,
      total_tokens: 225,
      provider_name: :open_ai
    }

    # With pricing information - costs calculated automatically
    %LlmComposer.CostInfo{
      input_tokens: 150_000,
      output_tokens: 75_000,
      input_price_per_million: Decimal.new("1.0"),
      output_price_per_million: Decimal.new("3.0"),
      currency: "USD",
      provider_name: :open_ai,
      provider_model: "gpt-4o-mini"
    }
    # Will automatically calculate:
    # input_cost: 0.15, output_cost: 0.225, total_cost: 0.375

    # Direct cost specification (bypasses automatic calculation)
    %LlmComposer.CostInfo{
      input_tokens: 150,
      output_tokens: 75,
      input_cost: Decimal.new("0.0015"),
      output_cost: Decimal.new("0.0030"),
      total_cost: Decimal.new("0.0045"),
      currency: "USD",
      provider_name: :open_ai
    }
  """

  @enforce_keys [
    :input_tokens,
    :output_tokens,
    :provider_model,
    :provider_name,
    :total_tokens
  ]

  defstruct [
    :currency,
    :input_cost,
    :input_tokens,
    :output_cost,
    :output_tokens,
    :provider_model,
    :provider_name,
    :total_cost,
    :total_tokens,
    input_price_per_million: nil,
    output_price_per_million: nil,
    metadata: %{}
  ]

  @type t() :: %__MODULE__{
          currency: String.t() | nil,
          input_cost: Decimal.t() | nil,
          input_price_per_million: Decimal.t() | nil,
          output_price_per_million: Decimal.t() | nil,
          input_tokens: non_neg_integer(),
          output_cost: Decimal.t() | nil,
          output_tokens: non_neg_integer(),
          provider_model: String.t(),
          provider_name: String.t() | atom(),
          total_cost: Decimal.t() | nil,
          total_tokens: non_neg_integer(),
          metadata: map()
        }

  @spec new(String.t() | atom(), String.t(), non_neg_integer(), non_neg_integer(), keyword()) :: t
  def new(provider_name, model, input_tokens, output_tokens, options \\ []) do
    cost_info =
      struct!(
        %LlmComposer.CostInfo{
          provider_name: provider_name,
          provider_model: model,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: input_tokens + output_tokens
        },
        options
      )

    # Validate that if any price is provided, both must be provided
    input_price = cost_info.input_price_per_million
    output_price = cost_info.output_price_per_million

    maybe_calculate(
      cond do
        is_nil(input_price) and is_nil(output_price) ->
          cost_info

        is_nil(input_price) or is_nil(output_price) ->
          raise ArgumentError,
                "Both input_price_per_million and output_price_per_million must be provided together"

        true ->
          cost_info
      end
    )
  end

  @spec maybe_calculate(t()) :: t()
  defp maybe_calculate(%LlmComposer.CostInfo{} = cost_info) do
    cost_info
    |> maybe_calculate_component(:input)
    |> maybe_calculate_component(:output)
    |> maybe_calculate_total()
  end

  @spec maybe_calculate_component(t(), :input | :output) :: t()
  defp maybe_calculate_component(%__MODULE__{} = cost_info, :input) do
    cond do
      not is_nil(cost_info.input_cost) ->
        cost_info

      is_nil(cost_info.input_price_per_million) ->
        cost_info

      true ->
        price = cost_info.input_price_per_million
        tokens = Decimal.new(cost_info.input_tokens)
        per_million = Decimal.new(1_000_000)

        input_cost =
          tokens
          |> Decimal.div(per_million)
          |> Decimal.mult(price)

        %{cost_info | input_cost: input_cost}
    end
  end

  defp maybe_calculate_component(%__MODULE__{} = cost_info, :output) do
    cond do
      not is_nil(cost_info.output_cost) ->
        cost_info

      is_nil(cost_info.output_price_per_million) ->
        cost_info

      true ->
        price = cost_info.output_price_per_million
        tokens = Decimal.new(cost_info.output_tokens)
        per_million = Decimal.new(1_000_000)

        output_cost =
          tokens
          |> Decimal.div(per_million)
          |> Decimal.mult(price)

        %{cost_info | output_cost: output_cost}
    end
  end

  @spec maybe_calculate_total(t()) :: t()
  defp maybe_calculate_total(%__MODULE__{} = cost_info) do
    cond do
      not is_nil(cost_info.total_cost) ->
        cost_info

      not is_nil(cost_info.input_cost) and not is_nil(cost_info.output_cost) ->
        %{cost_info | total_cost: Decimal.add(cost_info.input_cost, cost_info.output_cost)}

      true ->
        cost_info
    end
  end
end
