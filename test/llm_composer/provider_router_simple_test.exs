defmodule LlmComposer.ProviderRouterSimpleTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Providers.OpenAI
  alias LlmComposer.Providers.Google
  alias LlmComposer.ProviderRouter.Simple
  alias LlmComposer.Settings

  setup do
    # Start the provider router
    {:ok, _router_pid} = Simple.start_link([])

    # Set up bypass servers for both providers
    openai_bypass = Bypass.open()
    google_bypass = Bypass.open()

    {:ok, openai_bypass: openai_bypass, google_bypass: google_bypass}
  end

  test "router fails over from first provider to second when first fails", %{
    openai_bypass: openai_bypass,
    google_bypass: google_bypass
  } do
    # Mock OpenAI (first provider) to return an error
    Bypass.expect_once(openai_bypass, "POST", "/chat/completions", fn conn ->
      error_body = %{
        "error" => %{
          "message" => "Invalid API key",
          "type" => "invalid_request_error",
          "code" => "invalid_api_key"
        }
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(401, Jason.encode!(error_body))
    end)

    # Mock Google (second provider) to return success
    Bypass.expect_once(
      google_bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        # Verify it's hitting the correct endpoint
        contents = request_data["contents"]
        user_content = Enum.find(contents, &(&1["role"] == "user"))
        assert user_content["parts"] == [%{"text" => "hi"}]

        response_body = %{
          "candidates" => [
            %{
              "content" => %{
                "role" => "model",
                "parts" => [%{"text" => "Hello from Google!"}]
              },
              "finishReason" => "STOP",
              "index" => 0
            }
          ],
          "usageMetadata" => %{
            "promptTokenCount" => 20,
            "candidatesTokenCount" => 8,
            "totalTokenCount" => 28
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response_body))
      end
    )

    # Configure settings with multiple providers
    settings = %Settings{
      providers: [
        {OpenAI,
         [
           model: "gpt-4.1-mini",
           api_key: "test-key",
           url: endpoint_url(openai_bypass.port, :open_ai)
         ]},
        {Google,
         [
           model: "gemini-2.5-flash",
           api_key: "test-key",
           url: endpoint_url(google_bypass.port, :google)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    # Test the simple chat - should fail over to Google
    {:ok, response} = LlmComposer.simple_chat(settings, "hi")

    # Verify the response came from Google
    assert response.main_response.type == :assistant
    assert response.main_response.content == "Hello from Google!"
    assert response.input_tokens == 20
    assert response.output_tokens == 8
    assert response.provider == :google
  end

  test "router blocks failing provider and uses healthy one on subsequent calls", %{
    openai_bypass: openai_bypass,
    google_bypass: google_bypass
  } do
    # First call: OpenAI fails, Google succeeds
    Bypass.expect_once(openai_bypass, "POST", "/chat/completions", fn conn ->
      error_body = %{
        "error" => %{
          "message" => "Invalid API key",
          "type" => "invalid_request_error",
          "code" => "invalid_api_key"
        }
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(401, Jason.encode!(error_body))
    end)

    # Google responses for both calls (using expect instead of expect_once to allow multiple calls)
    google_call_count = :atomics.new(1, [])

    Bypass.expect(
      google_bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        call_num = :atomics.add_get(google_call_count, 1, 1)

        response_body =
          case call_num do
            1 ->
              %{
                "candidates" => [
                  %{
                    "content" => %{
                      "role" => "model",
                      "parts" => [%{"text" => "First response from Google"}]
                    }
                  }
                ],
                "usageMetadata" => %{
                  "promptTokenCount" => 10,
                  "candidatesTokenCount" => 5
                }
              }

            2 ->
              %{
                "candidates" => [
                  %{
                    "content" => %{
                      "role" => "model",
                      "parts" => [%{"text" => "Second response from Google"}]
                    }
                  }
                ],
                "usageMetadata" => %{
                  "promptTokenCount" => 10,
                  "candidatesTokenCount" => 5
                }
              }
          end

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response_body))
      end
    )

    settings = %Settings{
      providers: [
        {OpenAI,
         [
           model: "gpt-4.1-mini",
           api_key: "test-key",
           url: endpoint_url(openai_bypass.port, :open_ai)
         ]},
        {Google,
         [
           model: "gemini-2.5-flash",
           api_key: "test-key",
           url: endpoint_url(google_bypass.port, :google)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    # First call - should fail over to Google
    {:ok, response1} = LlmComposer.simple_chat(settings, "hi")
    assert response1.main_response.content == "First response from Google"
    assert response1.provider == :google

    # Second call - OpenAI should be blocked, Google should be used directly
    {:ok, response2} = LlmComposer.simple_chat(settings, "hello")
    assert response2.main_response.content == "Second response from Google"
    assert response2.provider == :google
  end

  test "router returns error when all providers fail", %{
    openai_bypass: openai_bypass,
    google_bypass: google_bypass
  } do
    # Mock both providers to fail
    Bypass.expect_once(openai_bypass, "POST", "/chat/completions", fn conn ->
      error_body = %{
        "error" => %{
          "message" => "Invalid API key",
          "type" => "invalid_request_error",
          "code" => "invalid_api_key"
        }
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(401, Jason.encode!(error_body))
    end)

    Bypass.expect_once(
      google_bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        error_body = %{
          "error" => %{
            "code" => 401,
            "message" => "Invalid API key",
            "status" => "UNAUTHENTICATED"
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(401, Jason.encode!(error_body))
      end
    )

    settings = %Settings{
      providers: [
        {OpenAI,
         [
           model: "gpt-4.1-mini",
           api_key: "test-key",
           url: endpoint_url(openai_bypass.port, :open_ai)
         ]},
        {Google,
         [
           model: "gemini-2.5-flash",
           api_key: "test-key",
           url: endpoint_url(google_bypass.port, :google)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    # Should return error when all providers fail
    result = LlmComposer.simple_chat(settings, "hi")
    assert {:error, _} = result
  end

  defp endpoint_url(port, provider) do
    case provider do
      :open_ai -> "http://localhost:#{port}/"
      :google -> "http://localhost:#{port}/v1beta/models/"
    end
  end
end
