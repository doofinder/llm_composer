defmodule LlmComposer.Cost.Fetchers.ModelsDevTest do
  # async: false: stubs the models.dev base URL via global Application env
  # (same reason test/llm_composer/providers/bedrock_http_client_test.exs is
  # async: false when it stubs HTTP with Bypass).
  #
  # Model names used here are deliberately unique across the whole test suite
  # (a "zz-" prefix) — the cache is one process-wide ETS table shared by every
  # test file (LlmComposer.Cache.Ets is a singleton), so reusing a name another
  # file also seeds would make assertions here depend on test execution order.
  use ExUnit.Case, async: false

  alias LlmComposer.Cache.Ets
  alias LlmComposer.Cost.Fetchers.ModelsDev
  alias LlmComposer.Cost.Pricing

  setup_all do
    Ets.start_link()
    :ok
  end

  setup do
    bypass = Bypass.open()

    # 127.0.0.1, not "localhost": some CI runners resolve "localhost" to ::1
    # first, which Bypass doesn't listen on, causing an intermittent
    # connection failure — fetch_dataset/0 then returns :error and nothing
    # gets cached, indistinguishable from a real network hiccup.
    Application.put_env(:llm_composer, :models_dev, base_url: "http://127.0.0.1:#{bypass.port}")
    on_exit(fn -> Application.delete_env(:llm_composer, :models_dev) end)
    {:ok, bypass: bypass}
  end

  describe "fetch_pricing/2 on a cache miss" do
    test "downloads the dataset, resolves the requested pair, and caches only that pair under the requested key",
         %{bypass: bypass} do
      dataset = %{
        "openai" => %{
          "models" => %{
            "zz-test-model" => %{
              "cost" => %{"input" => "0.250", "output" => "2.000"}
            }
          }
        }
      }

      Bypass.expect_once(bypass, "GET", "/api.json", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, JSON.encode!(dataset))
      end)

      # The requested name is dated; only "zz-test-model" (no date) is
      # indexed, so this also exercises Lookup's date-fallback resolution for
      # real, over the wire, not just against an in-memory map.
      result = ModelsDev.fetch_pricing(:open_ai, "zz-test-model-2026-03-17")

      assert result == %{
               input_price_per_million: Decimal.new("0.250"),
               output_price_per_million: Decimal.new("2.000")
             }

      # Load-bearing: caches under the *requested* (dated) key, not the name
      # Lookup actually resolved to — otherwise every call for the dated name
      # would miss forever and re-download the whole dataset.
      assert Ets.get({"openai", "zz-test-model-2026-03-17"}) ==
               {:ok, %{"input" => "0.250", "output" => "2.000"}}

      assert Ets.get({"openai", "zz-test-model"}) == :miss
    end

    test "does not re-download on a second call for the same pair", %{bypass: bypass} do
      dataset = %{
        "google" => %{
          "models" => %{
            "zz-test-gemini" => %{"cost" => %{"input" => 0.25, "output" => 1.5}}
          }
        }
      }

      # Bypass.expect_once/4 fails the test if the endpoint is hit more than
      # once, so calling fetch_pricing/2 twice and getting the same answer
      # both times proves the second call was served from cache.
      Bypass.expect_once(bypass, "GET", "/api.json", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, JSON.encode!(dataset))
      end)

      expected = %{
        input_price_per_million: Decimal.new("0.25"),
        output_price_per_million: Decimal.new("1.5")
      }

      assert ModelsDev.fetch_pricing(:google, "zz-test-gemini") == expected
      assert ModelsDev.fetch_pricing(:google, "zz-test-gemini") == expected
    end

    test "caches a miss too, so an unresolvable model doesn't re-download either", %{
      bypass: bypass
    } do
      dataset = %{"openai" => %{"models" => %{}}}

      Bypass.expect_once(bypass, "GET", "/api.json", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, JSON.encode!(dataset))
      end)

      assert ModelsDev.fetch_pricing(:open_ai, "zz-test-unknown-model") == nil
      assert Ets.get({"openai", "zz-test-unknown-model"}) == {:ok, nil}
      # Second call must not hit Bypass again (expect_once would fail it).
      assert ModelsDev.fetch_pricing(:open_ai, "zz-test-unknown-model") == nil
    end
  end

  describe "models_dev_provider override" do
    test "looks up and caches pricing under the given models.dev provider key", %{bypass: bypass} do
      dataset = %{
        "fireworks-ai" => %{
          "models" => %{
            "zz-test-fw-model" => %{
              "cost" => %{"input" => 0.22, "output" => 0.66, "cache_read" => 0.007}
            }
          }
        }
      }

      Bypass.expect_once(bypass, "GET", "/api.json", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, JSON.encode!(dataset))
      end)

      result =
        Pricing.fetch_pricing(:open_ai,
          model: "zz-test-fw-model",
          models_dev_provider: :"fireworks-ai"
        )

      assert Enum.sort(result) ==
               Enum.sort(
                 input_price_per_million: Decimal.new("0.22"),
                 output_price_per_million: Decimal.new("0.66"),
                 cache_read_price_per_million: Decimal.new("0.007"),
                 currency: "USD"
               )

      assert {:ok, _cost} = Ets.get({"fireworks-ai", "zz-test-fw-model"})
      assert Ets.get({"openai", "zz-test-fw-model"}) == :miss
    end
  end
end
