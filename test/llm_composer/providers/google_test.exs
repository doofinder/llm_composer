defmodule LlmComposer.Providers.GoogleTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Providers.Google
  alias LlmComposer.Settings

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "simple chat with 'hi' returns expected response", %{bypass: bypass} do
    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        contents = request_data["contents"]
        user_content = Enum.find(contents, &(&1["role"] == "user"))
        assert user_content["parts"] == [%{"text" => "hi"}]

        system_instruction = request_data["system_instruction"]
        assert system_instruction["parts"] == [%{"text" => "You are a helpful assistant"}]

        response_body = %{
          "candidates" => [
            %{
              "content" => %{
                "role" => "model",
                "parts" => [%{"text" => "Hello! How can I help you today?"}]
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

    settings = %Settings{
      providers: [
        {Google,
         [
           model: "gemini-2.5-flash",
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
    assert response.provider == :google
  end

  test "structured output is included in request", %{bypass: bypass} do
    schema = %{
      "type" => "object",
      "properties" => %{
        "answer" => %{"type" => "string"}
      },
      "required" => ["answer"]
    }

    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        generation_config = request_data["generationConfig"]
        assert generation_config["responseMimeType"] == "application/json"
        assert generation_config["responseSchema"]["type"] == "object"
        assert generation_config["responseSchema"]["properties"]["answer"]["type"] == "string"

        response_body = %{
          "candidates" => [
            %{
              "content" => %{
                "role" => "model",
                "parts" => [%{"text" => "{\"answer\": \"Hello!\"}"}]
              }
            }
          ],
          "usageMetadata" => %{
            "promptTokenCount" => 10,
            "candidatesTokenCount" => 5
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response_body))
      end
    )

    settings = %Settings{
      providers: [
        {Google,
         [
           model: "gemini-2.5-flash",
           response_schema: schema,
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  test "function calls are included in request", %{bypass: bypass} do
    functions = [
      %LlmComposer.Function{
        name: "get_weather",
        description: "Get weather information",
        schema: %{
          "type" => "object",
          "properties" => %{
            "location" => %{"type" => "string"}
          }
        },
        mf: {TestModule, :get_weather}
      }
    ]

    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        tools = request_data["tools"]
        assert is_list(tools)
        assert length(tools) == 1
        tools_hd = hd(tools)
        function_declarations = Map.get(tools_hd, "functionDeclarations")
        assert length(function_declarations) == 1
        func = hd(function_declarations)
        assert func["name"] == "get_weather"
        assert func["description"] == "Get weather information"

        response_body = %{
          "candidates" => [
            %{
              "content" => %{
                "role" => "model",
                "parts" => [%{"text" => "I'll check the weather for you."}]
              }
            }
          ],
          "usageMetadata" => %{
            "promptTokenCount" => 15,
            "candidatesTokenCount" => 6
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response_body))
      end
    )

    settings = %Settings{
      providers: [
        {Google,
         [
           model: "gemini-2.5-flash",
           functions: functions,
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, _response} = LlmComposer.simple_chat(settings, "What's the weather?")
  end

  test "handles API errors gracefully", %{bypass: bypass} do
    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        error_body = %{
          "error" => %{
            "code" => 400,
            "message" => "Invalid request",
            "status" => "INVALID_ARGUMENT"
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(400, Jason.encode!(error_body))
      end
    )

    settings = %Settings{
      providers: [
        {Google,
         [
           model: "gemini-2.5-flash",
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
        {Google,
         [
           model: "gemini-2.5-flash",
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
        {Google,
         [
           model: "gemini-2.5-flash",
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
        {Google,
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

  test "streaming endpoint is used when stream_response is true", %{bypass: bypass} do
    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:streamGenerateContent",
      fn conn ->
        response_body = %{
          "candidates" => [
            %{
              "content" => %{
                "role" => "model",
                "parts" => [%{"text" => "Hello"}]
              }
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response_body))
      end
    )

    settings = %Settings{
      providers: [
        {Google,
         [
           model: "gemini-2.5-flash",
           stream_response: true,
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  test "additional properties are removed from schema", %{bypass: bypass} do
    schema = %{
      "type" => "object",
      "properties" => %{
        "answer" => %{"type" => "string"}
      },
      "additionalProperties" => false,
      "nested" => %{
        "type" => "object",
        "additionalProperties" => true
      }
    }

    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        generation_config = request_data["generationConfig"]
        response_schema = generation_config["responseSchema"]

        refute Map.has_key?(response_schema, "additionalProperties")
        refute Map.has_key?(response_schema["nested"], "additionalProperties")

        response_body = %{
          "candidates" => [%{"content" => %{"role" => "model", "parts" => [%{"text" => "{}"}]}}],
          "usageMetadata" => %{"promptTokenCount" => 10, "candidatesTokenCount" => 2}
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response_body))
      end
    )

    settings = %Settings{
      providers: [
        {Google,
         [
           model: "gemini-2.5-flash",
           response_schema: schema,
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      system_prompt: "You are a helpful assistant"
    }

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  defp endpoint_url(port), do: "http://localhost:#{port}/v1beta/models/"
end
