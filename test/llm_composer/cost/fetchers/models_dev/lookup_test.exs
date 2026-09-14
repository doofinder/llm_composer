defmodule LlmComposer.Cost.Fetchers.ModelsDev.LookupTest do
  # async: false: the region_prefix_regex tests below mutate the global
  # :llm_composer, :models_dev Application env.
  use ExUnit.Case, async: false

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

  describe "get_cost/3 with a configured region_prefix_regex" do
    setup do
      on_exit(fn -> Application.delete_env(:llm_composer, :models_dev) end)
      :ok
    end

    test "uses the configured regex instead of the eu/us/ap/global default" do
      Application.put_env(:llm_composer, :models_dev, region_prefix_regex: ~r/^apac\./)

      data = %{
        "amazon-bedrock" => %{
          "models" => %{
            "some-model" => %{"cost" => %{"input" => 0.1, "output" => 0.2}}
          }
        }
      }

      # The default prefix ("eu.") no longer applies once a custom regex is
      # configured — this must NOT resolve.
      assert Lookup.get_cost(data, "amazon-bedrock", "eu.some-model") == nil

      # The configured prefix ("apac.") does.
      assert Lookup.get_cost(data, "amazon-bedrock", "apac.some-model") ==
               %{"input" => 0.1, "output" => 0.2}
    end
  end
end
