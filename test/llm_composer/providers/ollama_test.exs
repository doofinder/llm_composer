defmodule LlmComposer.Providers.OllamaTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Providers.Ollama
  alias LlmComposer.Settings

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "simple chat with 'hi' returns expected response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      messages = request_data["messages"]
      user_message = Enum.find(messages, &(&1["role"] == "user"))
      assert user_message["content"] == "hi"

      system_message = Enum.find(messages, &(&1["role"] == "system"))
      assert system_message["content"] == "You are a helpful assistant"

      assert request_data["model"] == "llama3.2"
      assert request_data["stream"] == false

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

    {:ok, response} = LlmComposer.simple_chat(settings, "hi")
    assert response.main_response.type == :assistant
    assert response.main_response.content == "Hello! How can I help you today?"
    assert response.provider == :ollama
  end

  test "streaming is enabled when stream_response is true", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

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

    result = LlmComposer.simple_chat(settings, "hi")
    assert {:error, _} = result
  end

  test "handles network errors", %{bypass: bypass} do
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

    result = LlmComposer.simple_chat(settings, "hi")
    assert {:error, _} = result
  end

  test "missing model raises error", %{bypass: bypass} do
    settings = %Settings{
      providers: [
        {Ollama,
         [
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    result = LlmComposer.simple_chat(settings, "hi")
    assert {:error, :model_not_provided} = result
  end

  test "uses default localhost URL when not specified", %{bypass: bypass} do
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

    result = LlmComposer.simple_chat(settings, "hi")
    assert {:error, _} = result
  end

  defp endpoint_url(port), do: "http://localhost:#{port}"
end
