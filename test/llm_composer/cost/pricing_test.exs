defmodule LlmComposer.PricingTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Cache.Ets
  alias LlmComposer.Cost.Fetchers.ModelsDev
  alias LlmComposer.Cost.Pricing

  setup_all do
    Ets.start_link()
    :ok
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

    test "returns models.dev pricing for open_ai_responses" do
      data = %{
        "openai" => %{
          "models" => %{
            "gpt-5.4-mini" => %{
              "cost" => %{
                "input" => "0.250",
                "output" => "2.000"
              }
            }
          }
        }
      }

      Ets.put("models_dev_api", data, 3600)

      result = Pricing.fetch_pricing(:open_ai_responses, model: "gpt-5.4-mini")

      assert result == [
               input_price_per_million: Decimal.new("0.250"),
               output_price_per_million: Decimal.new("2.000"),
               currency: "USD"
             ]
    end
  end

  describe "models_dev_fetcher/2 for bedrock" do
    test "returns pricing for bedrock provider" do
      data = %{
        "amazon-bedrock" => %{
          "models" => %{
            "amazon.nova-lite-v1:0" => %{
              "cost" => %{"input" => 0.06, "output" => 0.24, "cache_read" => 0.015}
            }
          }
        }
      }

      Ets.put("models_dev_api", data, 3600)

      result = Pricing.fetch_pricing(:bedrock, model: "amazon.nova-lite-v1:0")

      assert result == [
               cache_read_price_per_million: Decimal.new("0.015"),
               input_price_per_million: Decimal.new("0.06"),
               output_price_per_million: Decimal.new("0.24"),
               currency: "USD"
             ]
    end

    test "strips region prefix when exact match not found" do
      data = %{
        "amazon-bedrock" => %{
          "models" => %{
            "amazon.nova-lite-v1:0" => %{
              "cost" => %{"input" => 0.06, "output" => 0.24}
            }
          }
        }
      }

      Ets.put("models_dev_api", data, 3600)

      result = Pricing.fetch_pricing(:bedrock, model: "eu.amazon.nova-lite-v1:0")

      assert result == [
               input_price_per_million: Decimal.new("0.06"),
               output_price_per_million: Decimal.new("0.24"),
               currency: "USD"
             ]
    end

    test "uses region-prefixed entry when available" do
      data = %{
        "amazon-bedrock" => %{
          "models" => %{
            "eu.anthropic.claude-sonnet-4-6" => %{
              "cost" => %{"input" => 0.4, "output" => 2.0}
            },
            "anthropic.claude-sonnet-4-6" => %{
              "cost" => %{"input" => 0.3, "output" => 1.5}
            }
          }
        }
      }

      Ets.put("models_dev_api", data, 3600)

      result = Pricing.fetch_pricing(:bedrock, model: "eu.anthropic.claude-sonnet-4-6")

      assert result == [
               input_price_per_million: Decimal.new("0.4"),
               output_price_per_million: Decimal.new("2.0"),
               currency: "USD"
             ]
    end
  end

  describe "models_dev_fetcher/2" do
    test "returns nil for unsupported providers" do
      result = ModelsDev.fetch_pricing(:ollama, "llama3.1")
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
        "openai" => %{
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

      result = ModelsDev.fetch_pricing(:open_ai, "gpt-4")

      expected = %{
        input_price_per_million: Decimal.new("0.001"),
        output_price_per_million: Decimal.new("0.002"),
        cache_read_price_per_million: Decimal.new("0.0005")
      }

      assert result == expected
    end

    test "extracts pricing for open_ai_responses from openai dataset" do
      data = %{
        "openai" => %{
          "models" => %{
            "gpt-5.4-mini" => %{
              "cost" => %{
                "input" => "0.250",
                "output" => "2.000"
              }
            }
          }
        }
      }

      Ets.put("models_dev_api", data, 3600)

      result = ModelsDev.fetch_pricing(:open_ai_responses, "gpt-5.4-mini")

      assert result == %{
               input_price_per_million: Decimal.new("0.250"),
               output_price_per_million: Decimal.new("2.000")
             }
    end

    test "falls back from dated openai snapshot model names" do
      data = %{
        "openai" => %{
          "models" => %{
            "gpt-5.4-mini" => %{
              "cost" => %{
                "input" => "0.250",
                "output" => "2.000"
              }
            }
          }
        }
      }

      Ets.put("models_dev_api", data, 3600)

      result = ModelsDev.fetch_pricing(:open_ai_responses, "gpt-5.4-mini-2026-03-17")

      assert result == %{
               input_price_per_million: Decimal.new("0.250"),
               output_price_per_million: Decimal.new("2.000")
             }
    end

    test "returns nil when model not found in cached data" do
      data = %{"openai" => %{"models" => %{}}}
      Ets.put("models_dev_api", data, 3600)

      result = ModelsDev.fetch_pricing(:open_ai, "unknown-model")
      assert result == nil
    end

    test "returns nil when cost structure is invalid in cached data" do
      data = %{
        "openai" => %{
          "models" => %{
            "gpt-4" => %{
              "cost" => %{"invalid" => "structure"}
            }
          }
        }
      }

      Ets.put("models_dev_api", data, 3600)

      result = ModelsDev.fetch_pricing(:open_ai, "gpt-4")
      assert result == nil
    end
  end
end
