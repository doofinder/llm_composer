defmodule LlmComposer.Providers.UtilsTest do
  use ExUnit.Case

  alias LlmComposer.Providers.Utils

  setup do
    # Start the cache for testing
    start_supervised!(LlmComposer.Cache.Ets)
    :ok
  end

  describe "build_cost_info/3" do
    test "returns nil when track_costs is false" do
      opts = [track_costs: false]
      body = %{"usage" => %{"prompt_tokens" => 100, "completion_tokens" => 50}}

      assert Utils.build_cost_info(:open_ai, opts, body) == nil
    end

    test "returns nil when track_costs is not set" do
      opts = []
      body = %{"usage" => %{"prompt_tokens" => 100, "completion_tokens" => 50}}

      assert Utils.build_cost_info(:open_ai, opts, body) == nil
    end

    test "OpenAI provider - builds CostInfo with static pricing" do
      opts = [
        track_costs: true,
        model: "gpt-4",
        input_price_per_million: "1.5",
        output_price_per_million: "3.0"
      ]

      body = %{
        "model" => "gpt-4",
        "usage" => %{"prompt_tokens" => 1000, "completion_tokens" => 500}
      }

      cost_info = Utils.build_cost_info(:open_ai, opts, body)

      assert cost_info.provider_name == :open_ai
      assert cost_info.provider_model == "gpt-4"
      assert cost_info.input_tokens == 1000
      assert cost_info.output_tokens == 500
      assert cost_info.total_tokens == 1500
      assert Decimal.equal?(cost_info.input_price_per_million, Decimal.new("1.5"))
      assert Decimal.equal?(cost_info.output_price_per_million, Decimal.new("3.0"))
      assert cost_info.currency == "USD"
    end

    test "OpenAI provider - builds CostInfo without pricing options" do
      # Use a model that won't be found in models.dev to test fallback to nil pricing
      opts = [track_costs: true, model: "non-existent-model"]

      body = %{
        "model" => "non-existent-model",
        "usage" => %{"prompt_tokens" => 100, "completion_tokens" => 50}
      }

      cost_info = Utils.build_cost_info(:open_ai, opts, body)

      assert cost_info.provider_name == :open_ai
      assert cost_info.provider_model == "non-existent-model"
      assert cost_info.input_tokens == 100
      assert cost_info.output_tokens == 50
      assert cost_info.total_tokens == 150
      assert is_nil(cost_info.input_price_per_million)
      assert is_nil(cost_info.output_price_per_million)
    end

    test "OpenRouter provider - builds CostInfo with static pricing" do
      opts = [
        track_costs: true,
        model: "anthropic/claude-3-haiku",
        input_price_per_million: "0.25",
        output_price_per_million: "1.25"
      ]

      body = %{
        "model" => "anthropic/claude-3-haiku:beta",
        "usage" => %{"prompt_tokens" => 2000, "completion_tokens" => 1000}
      }

      cost_info = Utils.build_cost_info(:open_router, opts, body)

      assert cost_info.provider_name == :open_router
      assert cost_info.provider_model == "anthropic/claude-3-haiku:beta"
      assert cost_info.input_tokens == 2000
      assert cost_info.output_tokens == 1000
      assert cost_info.total_tokens == 3000
      assert Decimal.equal?(cost_info.input_price_per_million, Decimal.new("0.25"))
      assert Decimal.equal?(cost_info.output_price_per_million, Decimal.new("1.25"))
      assert cost_info.currency == "USD"
    end

    test "Google provider - builds CostInfo with static pricing" do
      opts = [
        track_costs: true,
        model: "gemini-2.5-flash",
        input_price_per_million: "0.075",
        output_price_per_million: "0.30"
      ]

      body = %{
        "usageMetadata" => %{
          "promptTokenCount" => 1500,
          "candidatesTokenCount" => 750
        }
      }

      cost_info = Utils.build_cost_info(:google, opts, body)

      assert cost_info.provider_name == :google
      assert cost_info.provider_model == "gemini-2.5-flash"
      assert cost_info.input_tokens == 1500
      assert cost_info.output_tokens == 750
      assert cost_info.total_tokens == 2250
      assert Decimal.equal?(cost_info.input_price_per_million, Decimal.new("0.075"))
      assert Decimal.equal?(cost_info.output_price_per_million, Decimal.new("0.30"))
      assert cost_info.currency == "USD"
    end

    test "Google provider - builds CostInfo without pricing options" do
      # Use a model that won't be found in models.dev to test fallback to nil pricing
      opts = [track_costs: true, model: "non-existent-model"]

      body = %{
        "usageMetadata" => %{
          "promptTokenCount" => 100,
          "candidatesTokenCount" => 50
        }
      }

      cost_info = Utils.build_cost_info(:google, opts, body)

      assert cost_info.provider_name == :google
      assert cost_info.provider_model == "non-existent-model"
      assert cost_info.input_tokens == 100
      assert cost_info.output_tokens == 50
      assert cost_info.total_tokens == 150
      assert is_nil(cost_info.input_price_per_million)
      assert is_nil(cost_info.output_price_per_million)
    end

    test "handles nil token values gracefully" do
      opts = [track_costs: true, model: "gpt-4"]
      body = %{"usage" => %{"prompt_tokens" => 0, "completion_tokens" => 0}}

      cost_info = Utils.build_cost_info(:open_ai, opts, body)

      assert cost_info.input_tokens == 0
      assert cost_info.output_tokens == 0
      assert cost_info.total_tokens == 0
    end

    test "handles missing usage data" do
      opts = [track_costs: true, model: "gpt-4"]
      body = %{}

      cost_info = Utils.build_cost_info(:open_ai, opts, body)

      assert cost_info.input_tokens == nil
      assert cost_info.output_tokens == nil
      assert cost_info.total_tokens == 0
    end
  end
end
