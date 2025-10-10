defmodule LlmComposer.PricingTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Cache.Ets
  alias LlmComposer.Pricing

  setup do
    # Start the cache for testing
    start_supervised!(Ets)
    :ok
  end

  describe "calculate_cost/3" do
    test "returns existing cost when provided" do
      existing_cost = Decimal.new("1.50")
      result = Pricing.calculate_cost(existing_cost, 1000, Decimal.new("0.002"))
      assert result == existing_cost
    end

    test "returns nil when price is nil" do
      result = Pricing.calculate_cost(nil, 1000, nil)
      assert result == nil
    end

    test "calculates cost correctly" do
      tokens = 150_000
      # $0.002 per million tokens
      price_per_million = Decimal.new("0.002")
      # 150_000 / 1_000_000 * 0.002 = 0.0003
      expected_cost = Decimal.new("0.00030")

      result = Pricing.calculate_cost(nil, tokens, price_per_million)
      assert result == expected_cost
    end

    test "handles zero tokens" do
      result = Pricing.calculate_cost(nil, 0, Decimal.new("0.002"))
      assert Decimal.equal?(result, Decimal.new("0"))
    end
  end

  describe "fetch_pricing/2" do
    test "returns explicit pricing when provided" do
      opts = [
        input_price_per_million: "0.001",
        output_price_per_million: "0.002"
      ]

      result = Pricing.fetch_pricing(:open_ai, opts)

      expected = [
        input_price_per_million: Decimal.new("0.001"),
        output_price_per_million: Decimal.new("0.002"),
        currency: "USD"
      ]

      assert result == expected
    end

    test "returns nil when no pricing available" do
      result = Pricing.fetch_pricing(:unknown_provider, [])
      assert result == nil
    end

    test "handles incomplete explicit pricing" do
      # Should not return explicit pricing if both input and output are not provided
      # missing output
      opts = [input_price_per_million: "0.001"]
      result = Pricing.fetch_pricing(:open_ai, opts)
      assert result == nil
    end
  end

  describe "models_dev_fetcher/2" do
    test "returns nil for unsupported providers" do
      result = Pricing.models_dev_fetcher(:ollama, "llama3.1")
      assert result == nil
    end

    test "returns nil when model is not provided" do
      # no model in opts
      result = Pricing.fetch_pricing(:open_ai, [])
      assert result == nil
    end
  end

  describe "models_dev_fetcher/2 with cached data" do
    test "extracts pricing correctly from cached data" do
      data = %{
        "open_ai" => %{
          "models" => %{
            "gpt-4" => %{
              "cost" => %{
                "input" => "0.001",
                "output" => "0.002",
                "cache_read" => "0.0005"
              }
            }
          }
        }
      }

      # Pre-populate cache
      Ets.put("models_dev_api", data, 3600)

      result = Pricing.models_dev_fetcher(:open_ai, "gpt-4")

      expected = %{
        input_price_per_million: Decimal.new("0.001"),
        output_price_per_million: Decimal.new("0.002")
      }

      assert result == expected
    end

    test "returns nil when model not found in cached data" do
      data = %{"open_ai" => %{"models" => %{}}}
      Ets.put("models_dev_api", data, 3600)

      result = Pricing.models_dev_fetcher(:open_ai, "unknown-model")
      assert result == nil
    end

    test "returns nil when cost structure is invalid in cached data" do
      data = %{
        "open_ai" => %{
          "models" => %{
            "gpt-4" => %{
              "cost" => %{"invalid" => "structure"}
            }
          }
        }
      }

      Ets.put("models_dev_api", data, 3600)

      result = Pricing.models_dev_fetcher(:open_ai, "gpt-4")
      assert result == nil
    end
  end
end
