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

  @spec new(String.t() | atom(), String.t(), non_neg_integer(), non_neg_integer(), keyword()) :: t
  def new(provider_name, model, input_tokens, output_tokens, options \\ []) do
    cost_info =
      struct!(
        %LlmComposer.CostInfo{
          provider_name: provider_name,
          provider_model: model,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: (input_tokens || 0) + (output_tokens || 0)
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
    |> calculate_component_costs()
    |> set_total_cost()
  end

  @spec calculate_component_costs(t()) :: t()
  defp calculate_component_costs(%LlmComposer.CostInfo{} = cost_info) do
    %{
      cost_info
      | input_cost:
          calculate_cost(
            cost_info.input_cost,
            cost_info.input_tokens,
            cost_info.input_price_per_million
          ),
        output_cost:
          calculate_cost(
            cost_info.output_cost,
            cost_info.output_tokens,
            cost_info.output_price_per_million
          )
    }
  end

  @spec set_total_cost(t()) :: t()
  # already set case
  defp set_total_cost(%__MODULE__{total_cost: total} = cost_info) when is_map(total),
    do: cost_info

  defp set_total_cost(%__MODULE__{input_cost: input, output_cost: output} = cost_info)
       when is_map(input) and is_map(output) do
    %{cost_info | total_cost: Decimal.add(input, output)}
  end

  defp set_total_cost(%__MODULE__{} = cost_info), do: cost_info
end
