defmodule LlmComposer.Providers.OpenRouterTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias LlmComposer.Cache.Ets
  alias LlmComposer.Providers.OpenRouter
  alias LlmComposer.Settings

  setup_all do
    case Ets.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  setup do
    bypass = Bypass.open()

    {:ok, bypass: bypass}
  end

  test "simple chat with 'hi' returns expected response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      messages = request_data["messages"]
      user_message = Enum.find(messages, &(&1["role"] == "user"))
      assert user_message["content"] == "hi"

      system_message = Enum.find(messages, &(&1["role"] == "system"))
      assert system_message["content"] == "You are a helpful assistant"

      response_body = %{
        "id" => "chatcmpl-router-123",
        "object" => "chat.completion",
        "created" => 1_677_628_800,
        "model" => "anthropic/claude-3-haiku:beta",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Hello! How can I help you today?"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 20,
          "completion_tokens" => 8,
          "total_tokens" => 28
        }
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    settings = %Settings{
      providers: [
        {OpenRouter,
         [
           model: "anthropic/claude-3-haiku:beta",
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, response} = LlmComposer.simple_chat(settings, "hi")
    assert response.main_response.type == :assistant
    assert response.main_response.content == "Hello! How can I help you today?"
    assert response.input_tokens == 20
    assert response.output_tokens == 8
    assert response.provider == :open_router
  end

  test "fallback models are included in request", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      assert request_data["models"] == ["anthropic/claude-3-haiku:beta", "openai/gpt-3.5-turbo"]

      response_body = %{
        "model" => "anthropic/claude-3-haiku:beta",
        "choices" => [%{"message" => %{"role" => "assistant", "content" => "OK"}}],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 2}
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    settings = %Settings{
      providers: [
        {OpenRouter,
         [
           model: "anthropic/claude-3-haiku:beta",
           models: ["anthropic/claude-3-haiku:beta", "openai/gpt-3.5-turbo"],
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  test "provider routing is included in request", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      expected_routing = %{"order" => ["Anthropic", "OpenAI"], "allow_fallbacks" => true}
      assert request_data["provider"] == expected_routing

      response_body = %{
        "choices" => [%{"message" => %{"role" => "assistant", "content" => "OK"}}],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 2}
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    settings = %Settings{
      providers: [
        {OpenRouter,
         [
           model: "anthropic/claude-3-haiku:beta",
           provider_routing: %{"order" => ["Anthropic", "OpenAI"], "allow_fallbacks" => true},
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  test "logs warning when fallback model is used", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      response_body = %{
        # Different from requested model
        "model" => "openai/gpt-3.5-turbo",
        "choices" => [%{"message" => %{"role" => "assistant", "content" => "OK"}}],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 2}
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    settings = %Settings{
      providers: [
        {OpenRouter,
         [
           model: "anthropic/claude-3-haiku:beta",
           models: ["anthropic/claude-3-haiku:beta", "openai/gpt-3.5-turbo"],
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    # Capture logs to verify warning is logged
    assert capture_log(fn ->
             {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
           end) =~
             "The 'openai/gpt-3.5-turbo' model has been used instead of 'anthropic/claude-3-haiku:beta'"
  end

  test "handles API errors gracefully", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      error_body = %{
        "error" => %{
          "message" => "Invalid API key",
          "type" => "authentication_error",
          "code" => 401
        }
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(401, Jason.encode!(error_body))
    end)

    settings = %Settings{
      providers: [
        {OpenRouter,
         [
           model: "anthropic/claude-3-haiku:beta",
           api_key: "invalid-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    result = LlmComposer.simple_chat(settings, "hi")
    assert {:error, _} = result
  end

  test "handles network errors", %{bypass: bypass} do
    Bypass.down(bypass)

    settings = %Settings{
      providers: [
        {OpenRouter,
         [
           model: "anthropic/claude-3-haiku:beta",
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    result = LlmComposer.simple_chat(settings, "hi")
    assert {:error, _} = result
  end

  test "missing API key raises error", %{bypass: bypass} do
    settings = %Settings{
      providers: [
        {OpenRouter,
         [
           model: "anthropic/claude-3-haiku:beta",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    assert_raise LlmComposer.Errors.MissingKeyError, fn ->
      LlmComposer.simple_chat(settings, "hi")
    end
  end

  test "missing model raises error", %{bypass: bypass} do
    settings = %Settings{
      providers: [
        {OpenRouter,
         [
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    result = LlmComposer.simple_chat(settings, "hi")
    assert {:error, :model_not_provided} = result
  end

  test "structured output is included in request", %{bypass: bypass} do
    schema = %{
      "type" => "object",
      "properties" => %{
        "answer" => %{"type" => "string"}
      },
      "required" => ["answer"]
    }

    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      response_format = request_data["response_format"]
      assert response_format["type"] == "json_schema"
      assert response_format["json_schema"]["name"] == "response"
      assert response_format["json_schema"]["strict"] == true
      assert response_format["json_schema"]["schema"] == schema

      response_body = %{
        "choices" => [%{"message" => %{"role" => "assistant", "content" => "OK"}}],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 2}
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    settings = %Settings{
      providers: [
        {OpenRouter,
         [
           model: "anthropic/claude-3-haiku:beta",
           response_schema: schema,
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  defp endpoint_url(port), do: "http://localhost:#{port}/"
end
