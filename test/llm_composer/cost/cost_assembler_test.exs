defmodule LlmComposer.Cost.CostAssemblerTest do
  use ExUnit.Case
  doctest LlmComposer.Cost.CostAssembler

  alias LlmComposer.Cache.Ets
  alias LlmComposer.Cost.CostAssembler
  alias LlmComposer.CostInfo

  setup_all do
    Ets.start_link()
    :ok
  end

  describe "extract_tokens/2 for OpenAI" do
    test "extracts tokens from OpenAI response format" do
      response = %{
        "usage" => %{
          "prompt_tokens" => 150,
          "completion_tokens" => 75
        }
      }

      {input, output} = CostAssembler.extract_tokens(:open_ai, response)

      assert input == 150
      assert output == 75
    end

    test "returns 0 for missing tokens in OpenAI response" do
      response = %{"usage" => %{}}

      {input, output} = CostAssembler.extract_tokens(:open_ai, response)

      assert input == 0
      assert output == 0
    end

    test "returns 0 when no usage field in OpenAI response" do
      response = %{}

      {input, output} = CostAssembler.extract_tokens(:open_ai, response)

      assert input == 0
      assert output == 0
    end
  end

  describe "extract_tokens/2 for OpenRouter" do
    test "extracts tokens from OpenRouter response format" do
      response = %{
        "usage" => %{
          "prompt_tokens" => 200,
          "completion_tokens" => 100
        }
      }

      {input, output} = CostAssembler.extract_tokens(:open_router, response)

      assert input == 200
      assert output == 100
    end
  end

  describe "extract_tokens/2 for Google" do
    test "extracts tokens from Google response format" do
      response = %{
        "usageMetadata" => %{
          "promptTokenCount" => 120,
          "candidatesTokenCount" => 60
        }
      }

      {input, output} = CostAssembler.extract_tokens(:google, response)

      assert input == 120
      assert output == 60
    end

    test "returns 0 for missing tokens in Google response" do
      response = %{"usageMetadata" => %{}}

      {input, output} = CostAssembler.extract_tokens(:google, response)

      assert input == 0
      assert output == 0
    end

    test "returns 0 when no usageMetadata field in Google response" do
      response = %{}

      {input, output} = CostAssembler.extract_tokens(:google, response)

      assert input == 0
      assert output == 0
    end
  end

  describe "extract_tokens/2 for unknown providers" do
    test "returns 0 for unsupported provider" do
      response = %{"usage" => %{"prompt_tokens" => 100, "completion_tokens" => 50}}

      {input, output} = CostAssembler.extract_tokens(:unknown, response)

      assert input == 0
      assert output == 0
    end
  end

  describe "get_cost_info/3 with track_costs: false" do
    test "returns nil when track_costs is false" do
      response = %{
        "model" => "gpt-4",
        "usage" => %{"prompt_tokens" => 100, "completion_tokens" => 50}
      }

      opts = [track_costs: false]

      result = CostAssembler.get_cost_info(:open_ai, response, opts)

      assert result == nil
    end
  end

  describe "get_cost_info/3 with track_costs: true for OpenAI" do
    test "assembles cost info for OpenAI without pricing" do
      response = %{
        "model" => "gpt-4o-mini",
        "usage" => %{"prompt_tokens" => 150, "completion_tokens" => 75}
      }

      opts = [track_costs: true]

      result = CostAssembler.get_cost_info(:open_ai, response, opts)

      assert is_struct(result, CostInfo)
      assert result.provider_name == :open_ai
      assert result.provider_model == "gpt-4o-mini"
      assert result.input_tokens == 150
      assert result.output_tokens == 75
      assert result.total_tokens == 225
      assert result.input_cost == nil
      assert result.output_cost == nil
      assert result.total_cost == nil
    end

    test "assembles cost info for OpenAI with explicit pricing" do
      response = %{
        "model" => "gpt-4o-mini",
        "usage" => %{"prompt_tokens" => 1_000_000, "completion_tokens" => 500_000}
      }

      opts = [
        track_costs: true,
        input_price_per_million: "0.150",
        output_price_per_million: "0.600"
      ]

      result = CostAssembler.get_cost_info(:open_ai, response, opts)

      assert result.provider_name == :open_ai
      assert result.provider_model == "gpt-4o-mini"
      assert result.input_tokens == 1_000_000
      assert result.output_tokens == 500_000
      assert Decimal.equal?(result.input_cost, Decimal.new("0.150"))
      assert Decimal.equal?(result.output_cost, Decimal.new("0.300"))
      assert Decimal.equal?(result.total_cost, Decimal.new("0.450"))
    end
  end

  describe "get_cost_info/3 for OpenRouter" do
    test "assembles cost info for OpenRouter with explicit pricing" do
      response = %{
        "model" => "anthropic/claude-3-haiku:beta",
        "provider" => "Anthropic",
        "usage" => %{"prompt_tokens" => 1_000_000, "completion_tokens" => 500_000}
      }

      opts = [
        track_costs: true,
        input_price_per_million: "0.250",
        output_price_per_million: "1.250"
      ]

      result = CostAssembler.get_cost_info(:open_router, response, opts)

      assert is_struct(result, CostInfo)
      assert result.provider_name == :open_router
      assert result.provider_model == "anthropic/claude-3-haiku:beta"
      assert result.input_tokens == 1_000_000
      assert result.output_tokens == 500_000
      assert Decimal.equal?(result.input_cost, Decimal.new("0.250"))
      assert Decimal.equal?(result.output_cost, Decimal.new("0.625"))
    end
  end

  describe "get_cost_info/3 for Google" do
    test "assembles cost info for Google with model from opts" do
      response = %{
        "usageMetadata" => %{
          "promptTokenCount" => 120,
          "candidatesTokenCount" => 60
        }
      }

      opts = [track_costs: true, model: "gemini-2.5-flash"]

      result = CostAssembler.get_cost_info(:google, response, opts)

      assert is_struct(result, CostInfo)
      assert result.provider_name == :google
      assert result.provider_model == "gemini-2.5-flash"
      assert result.input_tokens == 120
      assert result.output_tokens == 60
      assert result.total_tokens == 180
    end

    test "assembles cost info for Google with explicit pricing" do
      response = %{
        "usageMetadata" => %{
          "promptTokenCount" => 1_000_000,
          "candidatesTokenCount" => 500_000
        }
      }

      opts = [
        track_costs: true,
        model: "gemini-2.5-flash",
        input_price_per_million: "0.075",
        output_price_per_million: "0.300"
      ]

      result = CostAssembler.get_cost_info(:google, response, opts)

      assert result.provider_model == "gemini-2.5-flash"
      assert result.input_tokens == 1_000_000
      assert result.output_tokens == 500_000
      assert Decimal.equal?(result.input_cost, Decimal.new("0.075"))
      assert Decimal.equal?(result.output_cost, Decimal.new("0.150"))
      assert Decimal.equal?(result.total_cost, Decimal.new("0.225"))
    end
  end

  describe "get_cost_info/3 without track_costs option" do
    test "returns nil when track_costs is not set (defaults to false)" do
      response = %{
        "model" => "gpt-4",
        "usage" => %{"prompt_tokens" => 100, "completion_tokens" => 50}
      }

      opts = []

      result = CostAssembler.get_cost_info(:open_ai, response, opts)

      assert result == nil
    end
  end
end
