defmodule LlmComposer.Providers.OpenAITest do
  use ExUnit.Case, async: true

  alias LlmComposer.Providers.OpenAI
  alias LlmComposer.Settings

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
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "created" => 1_677_628_800,
        "model" => "gpt-3.5-turbo-0125",
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
        {OpenAI,
         [
           model: "gpt-4.1-mini",
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
    assert response.provider == :open_ai
  end

  test "handles API errors gracefully", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
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

    settings = %Settings{
      providers: [
        {OpenAI,
         [
           model: "gpt-4.1-mini",
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
        {OpenAI,
         [
           model: "gpt-4.1-mini",
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
        {OpenAI,
         [
           model: "gpt-4.1-mini",
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
        {OpenAI,
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

  defp endpoint_url(port), do: "http://localhost:#{port}/"
end
