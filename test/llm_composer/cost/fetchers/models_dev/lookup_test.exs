defmodule LlmComposer.Cost.Fetchers.ModelsDev.LookupTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Cost.Fetchers.ModelsDev.Lookup

  describe "get_cost/3" do
    test "returns the cost for an exact model match" do
      data = %{
        "openai" => %{
          "models" => %{
            "gpt-4" => %{"cost" => %{"input" => "0.001", "output" => "0.002"}}
          }
        }
      }

      assert Lookup.get_cost(data, "openai", "gpt-4") ==
               %{"input" => "0.001", "output" => "0.002"}
    end

    test "strips region prefix when exact match not found" do
      data = %{
        "amazon-bedrock" => %{
          "models" => %{
            "amazon.nova-lite-v1:0" => %{"cost" => %{"input" => 0.06, "output" => 0.24}}
          }
        }
      }

      assert Lookup.get_cost(data, "amazon-bedrock", "eu.amazon.nova-lite-v1:0") ==
               %{"input" => 0.06, "output" => 0.24}
    end

    test "prefers a region-prefixed entry when one is indexed directly" do
      data = %{
        "amazon-bedrock" => %{
          "models" => %{
            "eu.anthropic.claude-sonnet-4-6" => %{"cost" => %{"input" => 0.4, "output" => 2.0}},
            "anthropic.claude-sonnet-4-6" => %{"cost" => %{"input" => 0.3, "output" => 1.5}}
          }
        }
      }

      assert Lookup.get_cost(data, "amazon-bedrock", "eu.anthropic.claude-sonnet-4-6") ==
               %{"input" => 0.4, "output" => 2.0}
    end

    test "falls back from a dated OpenAI snapshot model name" do
      data = %{
        "openai" => %{
          "models" => %{
            "gpt-5.4-mini" => %{"cost" => %{"input" => "0.250", "output" => "2.000"}}
          }
        }
      }

      assert Lookup.get_cost(data, "openai", "gpt-5.4-mini-2026-03-17") ==
               %{"input" => "0.250", "output" => "2.000"}
    end

    test "strips region prefix then date suffix when neither alone matches" do
      data = %{
        "amazon-bedrock" => %{
          "models" => %{
            "amazon.nova-lite-v1:0" => %{"cost" => %{"input" => 0.06, "output" => 0.24}}
          }
        }
      }

      assert Lookup.get_cost(data, "amazon-bedrock", "eu.amazon.nova-lite-v1:0-2026-01-01") ==
               %{"input" => 0.06, "output" => 0.24}
    end

    test "returns nil when no variant of the model is indexed" do
      data = %{"openai" => %{"models" => %{}}}

      assert Lookup.get_cost(data, "openai", "unknown-model") == nil
    end
  end
end
