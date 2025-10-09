defmodule LlmComposer.CostInfoTest do
  use ExUnit.Case
  doctest LlmComposer.CostInfo

  alias LlmComposer.CostInfo

  describe "new/5" do
    test "creates struct with required fields" do
      cost_info = CostInfo.new(:open_ai, "gpt-4", 100, 50)

      assert cost_info.provider_name == :open_ai
      assert cost_info.provider_model == "gpt-4"
      assert cost_info.input_tokens == 100
      assert cost_info.output_tokens == 50
      assert cost_info.total_tokens == 150
    end

    test "creates struct with options" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 100, 50,
          currency: "USD",
          input_price_per_million: Decimal.new("1.0"),
          output_price_per_million: Decimal.new("2.0"),
          metadata: %{batch: true}
        )

      assert cost_info.currency == "USD"
      assert Decimal.equal?(cost_info.input_price_per_million, Decimal.new("1.0"))
      assert Decimal.equal?(cost_info.output_price_per_million, Decimal.new("2.0"))
      assert cost_info.metadata == %{batch: true}
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(CostInfo, %{})
      end
    end
  end

  describe "input cost calculation" do
    test "calculates input cost when price provided" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 1_000_000, 0, input_price_per_million: Decimal.new("1.5"))

      assert Decimal.equal?(cost_info.input_cost, Decimal.new("1.5"))
    end

    test "does not calculate when input_cost already set" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 1_000_000, 0,
          input_price_per_million: Decimal.new("1.5"),
          input_cost: Decimal.new("2.0")
        )

      assert Decimal.equal?(cost_info.input_cost, Decimal.new("2.0"))
    end

    test "does not calculate when input_price_per_million is nil" do
      cost_info = CostInfo.new(:open_ai, "gpt-4", 1_000_000, 0)

      assert is_nil(cost_info.input_cost)
    end

    test "calculates zero cost for zero tokens" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 0, 0, input_price_per_million: Decimal.new("1.5"))

      assert Decimal.equal?(cost_info.input_cost, Decimal.new("0"))
    end

    test "calculates fractional cost" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 500_000, 0, input_price_per_million: Decimal.new("2.0"))

      assert Decimal.equal?(cost_info.input_cost, Decimal.new("1.0"))
    end
  end

  describe "output cost calculation" do
    test "calculates output cost when price provided" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 0, 2_000_000,
          output_price_per_million: Decimal.new("3.0")
        )

      assert Decimal.equal?(cost_info.output_cost, Decimal.new("6.0"))
    end

    test "does not calculate when output_cost already set" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 0, 2_000_000,
          output_price_per_million: Decimal.new("3.0"),
          output_cost: Decimal.new("7.0")
        )

      assert Decimal.equal?(cost_info.output_cost, Decimal.new("7.0"))
    end

    test "does not calculate when output_price_per_million is nil" do
      cost_info = CostInfo.new(:open_ai, "gpt-4", 0, 2_000_000)

      assert is_nil(cost_info.output_cost)
    end
  end

  describe "total cost calculation" do
    test "calculates total when both input and output costs exist" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 1_000_000, 1_000_000,
          input_price_per_million: Decimal.new("1.0"),
          output_price_per_million: Decimal.new("2.0")
        )

      assert Decimal.equal?(cost_info.total_cost, Decimal.new("3.0"))
    end

    test "calculates total when only input cost exists" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 1_000_000, 0, input_price_per_million: Decimal.new("1.5"))

      assert Decimal.equal?(cost_info.total_cost, Decimal.new("1.5"))
    end

    test "calculates total when only output cost exists" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 0, 1_000_000,
          output_price_per_million: Decimal.new("2.5")
        )

      assert Decimal.equal?(cost_info.total_cost, Decimal.new("2.5"))
    end

    test "does not calculate when total_cost already set" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 1_000_000, 1_000_000,
          input_price_per_million: Decimal.new("1.0"),
          output_price_per_million: Decimal.new("2.0"),
          total_cost: Decimal.new("5.0")
        )

      assert Decimal.equal?(cost_info.total_cost, Decimal.new("5.0"))
    end

    test "leaves total_cost nil when no costs calculated" do
      cost_info = CostInfo.new(:open_ai, "gpt-4", 100, 50)

      assert is_nil(cost_info.total_cost)
    end
  end

  describe "integration tests" do
    test "full cost calculation with pricing" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4o-mini", 150_000, 75_000,
          input_price_per_million: Decimal.new("1.0"),
          output_price_per_million: Decimal.new("3.0"),
          currency: "USD"
        )

      assert cost_info.input_tokens == 150_000
      assert cost_info.output_tokens == 75_000
      assert cost_info.total_tokens == 225_000
      assert Decimal.equal?(cost_info.input_cost, Decimal.new("0.15"))
      assert Decimal.equal?(cost_info.output_cost, Decimal.new("0.225"))
      assert Decimal.equal?(cost_info.total_cost, Decimal.new("0.375"))
      assert cost_info.currency == "USD"
      assert cost_info.provider_name == :open_ai
      assert cost_info.provider_model == "gpt-4o-mini"
    end

    test "direct cost specification bypasses calculation" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 150, 75,
          input_cost: Decimal.new("0.0015"),
          output_cost: Decimal.new("0.0030"),
          total_cost: Decimal.new("0.0045"),
          currency: "USD"
        )

      assert Decimal.equal?(cost_info.input_cost, Decimal.new("0.0015"))
      assert Decimal.equal?(cost_info.output_cost, Decimal.new("0.0030"))
      assert Decimal.equal?(cost_info.total_cost, Decimal.new("0.0045"))
    end
  end

  describe "edge cases" do
    test "handles large token counts" do
      cost_info =
        CostInfo.new(:open_ai, "gpt-4", 100_000_000, 50_000_000,
          input_price_per_million: Decimal.new("0.5"),
          output_price_per_million: Decimal.new("1.5")
        )

      assert Decimal.equal?(cost_info.input_cost, Decimal.new("50.0"))
      assert Decimal.equal?(cost_info.output_cost, Decimal.new("75.0"))
      assert Decimal.equal?(cost_info.total_cost, Decimal.new("125.0"))
    end

    test "handles fractional pricing" do
      input_tokens = 333_333
      output_tokens = 666_667
      input_price = Decimal.new("0.123456")
      output_price = Decimal.new("0.654321")
      per_million = Decimal.new(1_000_000)

      expected_input_cost =
        Decimal.mult(Decimal.div(Decimal.new(input_tokens), per_million), input_price)

      expected_output_cost =
        Decimal.mult(Decimal.div(Decimal.new(output_tokens), per_million), output_price)

      expected_total_cost = Decimal.add(expected_input_cost, expected_output_cost)

      cost_info =
        CostInfo.new(:open_ai, "gpt-4", input_tokens, output_tokens,
          input_price_per_million: input_price,
          output_price_per_million: output_price
        )

      assert Decimal.equal?(cost_info.input_cost, expected_input_cost)
      assert Decimal.equal?(cost_info.output_cost, expected_output_cost)
      assert Decimal.equal?(cost_info.total_cost, expected_total_cost)
    end

    test "provider_name as string" do
      cost_info = CostInfo.new("open_ai", "gpt-4", 100, 50)

      assert cost_info.provider_name == "open_ai"
    end
  end
end
