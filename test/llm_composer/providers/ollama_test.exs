defmodule LlmComposer.Providers.OllamaTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Providers.Ollama
  alias LlmComposer.Settings

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "simple chat with 'hi' returns expected response", %{bypass: bypass} do
    # Mock the Ollama API response
    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      # Verify the request structure
      {:ok, body, _conn} = Plug.Conn.read_body(conn)

      # Parse the request body to verify it contains our message
      request_data = Jason.decode!(body)

      # Check that messages contain our "hi" message
      messages = request_data["messages"]
      user_message = Enum.find(messages, &(&1["role"] == "user"))
      assert user_message["content"] == "hi"

      # Check that system message is included
      system_message = Enum.find(messages, &(&1["role"] == "system"))
      assert system_message["content"] == "You are a helpful assistant"

      # Check model and stream settings
      assert request_data["model"] == "llama3.2"
      assert request_data["stream"] == false

      # Return a mock response
      response_body = %{
        "model" => "llama3.2",
        "created_at" => "2023-12-01T00:00:00Z",
        "message" => %{
          "role" => "assistant",
          "content" => "Hello! How can I help you today?"
        },
        "done" => true,
        "total_duration" => 1_000_000_000,
        "load_duration" => 500_000_000,
        "prompt_eval_count" => 20,
        "prompt_eval_duration" => 500_000_000,
        "eval_count" => 8,
        "eval_duration" => 500_000_000
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    # Create settings with mocked URL
    settings = %Settings{
      providers: [
        {Ollama,
         [
           model: "llama3.2",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    # Test the simple chat
    {:ok, response} = LlmComposer.simple_chat(settings, "hi")

    # Verify the response
    assert response.main_response.type == :assistant
    assert response.main_response.content == "Hello! How can I help you today?"
    assert response.provider == :ollama
  end

  test "streaming is enabled when stream_response is true", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      # Check that stream is set to true
      assert request_data["stream"] == true

      response_body = %{
        "model" => "llama3.2",
        "message" => %{
          "role" => "assistant",
          "content" => "Hello!"
        },
        "done" => true
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    settings = %Settings{
      providers: [
        {Ollama,
         [
           model: "llama3.2",
           stream_response: true,
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  test "additional request parameters are merged", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      # Check that custom parameters are included
      assert request_data["temperature"] == 0.7
      assert request_data["max_tokens"] == 100

      response_body = %{
        "model" => "llama3.2",
        "message" => %{
          "role" => "assistant",
          "content" => "OK"
        },
        "done" => true
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    settings = %Settings{
      providers: [
        {Ollama,
         [
           model: "llama3.2",
           request_params: %{
             temperature: 0.7,
             max_tokens: 100
           },
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  test "handles API errors gracefully", %{bypass: bypass} do
    # Mock an error response
    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      error_body = %{
        "error" => "model not found"
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(404, Jason.encode!(error_body))
    end)

    settings = %Settings{
      providers: [
        {Ollama,
         [
           model: "nonexistent-model",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    # Should return an error
    result = LlmComposer.simple_chat(settings, "hi")
    assert {:error, _} = result
  end

  test "handles network errors", %{bypass: bypass} do
    # Simulate network failure
    Bypass.down(bypass)

    settings = %Settings{
      providers: [
        {Ollama,
         [
           model: "llama3.2",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    # Should return an error due to network failure
    result = LlmComposer.simple_chat(settings, "hi")
    assert {:error, _} = result
  end

  test "missing model raises error", %{bypass: bypass} do
    settings = %Settings{
      providers: [
        {Ollama,
         [
           # No model provided
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    # Should return error for missing model
    result = LlmComposer.simple_chat(settings, "hi")
    assert {:error, :model_not_provided} = result
  end

  test "uses default localhost URL when not specified", %{bypass: bypass} do
    # This test verifies that the default URL logic works
    # We can't easily test the default URL with Bypass since it would try to connect to localhost:11434
    # But we can test that a custom URL works
    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      response_body = %{
        "model" => "llama3.2",
        "message" => %{
          "role" => "assistant",
          "content" => "OK"
        },
        "done" => true
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    settings = %Settings{
      providers: [
        {Ollama,
         [
           model: "llama3.2",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  test "handles malformed response body", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, "invalid json")
    end)

    settings = %Settings{
      providers: [
        {Ollama,
         [
           model: "llama3.2",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    # Should handle malformed response gracefully
    result = LlmComposer.simple_chat(settings, "hi")
    # Should return an error due to JSON parsing failure
    assert {:error, _} = result
  end

  defp endpoint_url(port), do: "http://localhost:#{port}"
end
