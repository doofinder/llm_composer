defmodule LlmComposer.Providers.OpenAITest do
  use ExUnit.Case, async: true

  alias LlmComposer.Function
  alias LlmComposer.FunctionCallHelpers
  alias LlmComposer.Message
  alias LlmComposer.Providers.OpenAI
  alias LlmComposer.Providers.OpenAIResponses
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

  test "OpenAIResponses uses /responses endpoint and normalizes response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/responses", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      assert request_data["model"] == "gpt-5-nano"
      assert request_data["reasoning"]["effort"] == "low"
      assert is_list(request_data["input"])

      response_body = %{
        "id" => "resp_123",
        "object" => "response",
        "model" => "gpt-5-nano",
        "output_text" => "Quantum computing uses qubits to encode information probabilistically.",
        "usage" => %{
          "input_tokens" => 15,
          "output_tokens" => 9,
          "total_tokens" => 24
        }
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    settings = %Settings{
      providers: [
        {OpenAIResponses,
         [
           model: "gpt-5-nano",
           api_key: "test-key",
           url: endpoint_url(bypass.port),
           reasoning_effort: "low"
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, response} = LlmComposer.simple_chat(settings, "Explain quantum computing")

    assert response.main_response.type == :assistant
    assert response.main_response.content =~ "Quantum computing"
    assert response.input_tokens == 15
    assert response.output_tokens == 9
    assert response.provider == :open_ai_responses
  end

  test "OpenAIResponses supports manual function-call flow", %{bypass: bypass} do
    Bypass.expect(bypass, "POST", "/responses", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      if Enum.any?(request_data["input"], &(&1["type"] == "function_call_output")) do
        assert Enum.any?(request_data["input"], fn item ->
                 item["type"] == "function_call_output" and
                   item["call_id"] == "call_123" and
                   item["output"] == "3"
               end)

        response_body = %{
          "id" => "resp_fc_2",
          "object" => "response",
          "model" => "gpt-5-nano",
          "output_text" => "The result is 3.",
          "usage" => %{
            "input_tokens" => 40,
            "output_tokens" => 8,
            "total_tokens" => 48
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response_body))
      else
        assert request_data["model"] == "gpt-5-nano"
        assert Enum.any?(request_data["tools"], &(&1["name"] == "calculator"))

        response_body = %{
          "id" => "resp_fc_1",
          "object" => "response",
          "model" => "gpt-5-nano",
          "output" => [
            %{
              "id" => "fc_123",
              "type" => "function_call",
              "call_id" => "call_123",
              "name" => "calculator",
              "arguments" => ~s({"expression":"1 + 2"}),
              "status" => "completed"
            }
          ],
          "usage" => %{
            "input_tokens" => 25,
            "output_tokens" => 10,
            "total_tokens" => 35
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response_body))
      end
    end)

    function = %Function{
      mf: {__MODULE__, :calculator},
      name: "calculator",
      description: "Evaluate a math expression",
      schema: %{
        "type" => "object",
        "properties" => %{"expression" => %{"type" => "string"}},
        "required" => ["expression"]
      }
    }

    provider_opts = [model: "gpt-5-nano", api_key: "test-key", url: endpoint_url(bypass.port)]

    settings = %Settings{
      providers: [{OpenAIResponses, Keyword.put(provider_opts, :functions, [function])}],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, first_response} = LlmComposer.simple_chat(settings, "How much is 1 + 2?")
    [function_call] = first_response.function_calls

    executed_call = %{function_call | result: 3}
    tool_messages = FunctionCallHelpers.build_tool_result_messages([executed_call])
    user_message = %Message{type: :user, content: "How much is 1 + 2?"}

    assistant_with_tools =
      FunctionCallHelpers.build_assistant_with_tools(
        OpenAIResponses,
        first_response,
        user_message,
        Keyword.put(provider_opts, :functions, [function])
      )

    messages = [user_message, assistant_with_tools] ++ tool_messages

    {:ok, final_response} = LlmComposer.run_completion(settings, messages)

    assert first_response.provider == :open_ai_responses
    assert [%{name: "calculator", id: "call_123"}] = first_response.function_calls
    assert final_response.main_response.content == "The result is 3."
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
