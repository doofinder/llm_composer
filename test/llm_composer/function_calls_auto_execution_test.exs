defmodule LlmComposer.FunctionCallsAutoExecutionTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Settings

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "auto executes function calls and completes chat loop", %{bypass: bypass} do
    # Mock first call that returns function calls (Google format)
    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        # Verify the request includes our function definition
        assert request_data["tools"] != nil
        function_decls = request_data["tools"]["function_declarations"]
        assert length(function_decls) == 1
        assert hd(function_decls)["name"] == "calculator"

        # Return function call response
        json_response = %{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [
                  %{
                    "functionCall" => %{
                      "name" => "calculator",
                      "args" => %{"expression" => "2 + 3"}
                    }
                  }
                ],
                "role" => "model"
              },
              "finishReason" => "STOP",
              "index" => 0
            }
          ],
          "modelVersion" => "gemini-2.5-flash",
          "usageMetadata" => %{
            "promptTokenCount" => 50,
            "candidatesTokenCount" => 10,
            "totalTokenCount" => 60
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(json_response))
      end
    )

    # Mock second call with function result and final response
    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        # Return final response
        json_response = %{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [%{"text" => "2 + 3 equals 5"}],
                "role" => "model"
              },
              "finishReason" => "STOP",
              "index" => 0
            }
          ],
          "modelVersion" => "gemini-2.5-flash",
          "usageMetadata" => %{
            "promptTokenCount" => 70,
            "candidatesTokenCount" => 5,
            "totalTokenCount" => 75
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(json_response))
      end
    )

    # Define test function
    calculator_function = %LlmComposer.Function{
      mf: {__MODULE__, :calculator},
      name: "calculator",
      description: "A calculator that evaluates math expressions",
      schema: %{
        "type" => "object",
        "properties" => %{
          "expression" => %{
            "type" => "string",
            "description" => "Math expression to evaluate"
          }
        },
        "required" => ["expression"]
      }
    }

    settings = %Settings{
      providers: [
        {LlmComposer.Providers.Google,
         [
           model: "gemini-2.5-flash",
           api_key: "test-key",
           url: "http://localhost:#{bypass.port}/v1beta/models/"
         ]}
      ],
      functions: [calculator_function],
      auto_exec_functions: true,
      system_prompt: "You are a helpful assistant"
    }

    {:ok, response} = LlmComposer.simple_chat(settings, "What is 2 + 3?")

    assert response.main_response.content == "2 + 3 equals 5"
    assert response.input_tokens == 70
    assert response.output_tokens == 5
    assert response.provider == :google
  end

  test "handles multiple function calls in sequence", %{bypass: bypass} do
    # Mock first call - returns function call
    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        json_response = %{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [
                  %{
                    "functionCall" => %{
                      "name" => "calculator",
                      "args" => %{"expression" => "10 / 2"}
                    }
                  }
                ],
                "role" => "model"
              },
              "finishReason" => "STOP",
              "index" => 0
            }
          ],
          "usageMetadata" => %{
            "promptTokenCount" => 45,
            "candidatesTokenCount" => 8,
            "totalTokenCount" => 53
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(json_response))
      end
    )

    # Mock second call - returns another function call
    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        request_data = Jason.decode!(body)

        # Verify first function result is present
        contents = request_data["contents"]

        function_result_part =
          Enum.find(contents, fn content ->
            parts = content["parts"]
            Enum.any?(parts, &Map.has_key?(&1, "functionResponse"))
          end)

        assert function_result_part != nil
        function_response = hd(function_result_part["parts"])["functionResponse"]
        assert function_response["response"]["result"] == 5.0

        # Return another function call
        json_response = %{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [
                  %{
                    "functionCall" => %{
                      "name" => "calculator",
                      "args" => %{"expression" => "5 * 3"}
                    }
                  }
                ],
                "role" => "model"
              },
              "finishReason" => "STOP",
              "index" => 0
            }
          ],
          "usageMetadata" => %{
            "promptTokenCount" => 65,
            "candidatesTokenCount" => 8,
            "totalTokenCount" => 73
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(json_response))
      end
    )

    # Mock third call - final response
    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        # Return final calculation result
        json_response = %{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [%{"text" => "The final result is 15"}],
                "role" => "model"
              },
              "finishReason" => "STOP",
              "index" => 0
            }
          ],
          "usageMetadata" => %{
            "promptTokenCount" => 85,
            "candidatesTokenCount" => 6,
            "totalTokenCount" => 91
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(json_response))
      end
    )

    calculator_function = %LlmComposer.Function{
      mf: {__MODULE__, :calculator},
      name: "calculator",
      description: "Calculator function",
      schema: %{
        "type" => "object",
        "properties" => %{"expression" => %{"type" => "string"}},
        "required" => ["expression"]
      }
    }

    settings = %Settings{
      providers: [
        {LlmComposer.Providers.Google,
         [
           model: "gemini-2.5-flash",
           api_key: "test-key",
           url: "http://localhost:#{bypass.port}/v1beta/models/"
         ]}
      ],
      functions: [calculator_function],
      auto_exec_functions: true,
      system_prompt: "You are a helpful assistant"
    }

    {:ok, response} = LlmComposer.simple_chat(settings, "Calculate 10 / 2, then multiply by 3")

    assert response.main_response.content == "The final result is 15"
    assert response.input_tokens == 85
    assert response.output_tokens == 6
  end

  test "exercises completion path when functions are executed with OpenAI", %{bypass: bypass} do
    # Mock first call that returns function calls (OpenAI format)
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      json_response = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "created" => 1_677_628_800,
        "model" => "gpt-4.1-mini",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call_123",
                  "type" => "function",
                  "function" => %{
                    "name" => "calculator",
                    "arguments" => "{\"expression\": \"2 * 3\"}"
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ],
        "usage" => %{"prompt_tokens" => 50, "completion_tokens" => 10}
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(json_response))
    end)

    # Mock second call for completion after function execution
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      messages = request_data["messages"]
      assert length(messages) > 1

      json_response = %{
        "id" => "chatcmpl-456",
        "object" => "chat.completion",
        "created" => 1_677_628_801,
        "model" => "gpt-4.1-mini",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "2 * 3 equals 6"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{"prompt_tokens" => 70, "completion_tokens" => 5}
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(json_response))
    end)

    calculator_function = %LlmComposer.Function{
      mf: {__MODULE__, :calculator},
      name: "calculator",
      description: "Calculator function",
      schema: %{
        "type" => "object",
        "properties" => %{"expression" => %{"type" => "string"}},
        "required" => ["expression"]
      }
    }

    settings = %Settings{
      providers: [
        {LlmComposer.Providers.OpenAI,
         [
           model: "gpt-4.1-mini",
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      functions: [calculator_function],
      auto_exec_functions: true,
      system_prompt: "You are a helpful assistant"
    }

    {:ok, response} = LlmComposer.simple_chat(settings, "What is 2 * 3?")

    assert response.main_response.content == "2 * 3 equals 6"
    assert response.input_tokens == 70
    assert response.output_tokens == 5
    assert response.provider == :open_ai
  end

  test "exercises completion path when functions are executed with OpenRouter", %{bypass: bypass} do
    # Mock first call that returns function calls (OpenRouter/OpenAI format)
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      json_response = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "created" => 1_677_628_800,
        "model" => "openrouter-model",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call_123",
                  "type" => "function",
                  "function" => %{
                    "name" => "calculator",
                    "arguments" => "{\"expression\": \"4 + 1\"}"
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ],
        "usage" => %{"prompt_tokens" => 50, "completion_tokens" => 10}
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(json_response))
    end)

    # Mock second call for completion after function execution
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      # Ensure the second request contains the appended function result
      messages = request_data["messages"]
      assert length(messages) > 1

      json_response = %{
        "id" => "chatcmpl-456",
        "object" => "chat.completion",
        "created" => 1_677_628_801,
        "model" => "openrouter-model",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "4 + 1 equals 5"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{"prompt_tokens" => 70, "completion_tokens" => 5}
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(json_response))
    end)

    calculator_function = %LlmComposer.Function{
      mf: {__MODULE__, :calculator},
      name: "calculator",
      description: "Calculator function",
      schema: %{
        "type" => "object",
        "properties" => %{"expression" => %{"type" => "string"}},
        "required" => ["expression"]
      }
    }

    settings = %Settings{
      providers: [
        {LlmComposer.Providers.OpenRouter,
         [
           model: "openrouter-model",
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ]}
      ],
      functions: [calculator_function],
      auto_exec_functions: true,
      system_prompt: "You are a helpful assistant"
    }

    {:ok, response} = LlmComposer.simple_chat(settings, "What is 4 + 1?")

    assert response.main_response.content == "4 + 1 equals 5"
    assert response.input_tokens == 70
    assert response.output_tokens == 5
    assert response.provider == :open_router
  end

  test "skips function execution when auto_exec_functions is false", %{bypass: bypass} do
    # Mock single call that returns function calls
    Bypass.expect_once(
      bypass,
      "POST",
      "/v1beta/models/gemini-2.5-flash:generateContent",
      fn conn ->
        json_response = %{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [
                  %{
                    "functionCall" => %{
                      "name" => "calculator",
                      "args" => %{"expression" => "1 + 1"}
                    }
                  }
                ],
                "role" => "model"
              },
              "finishReason" => "STOP",
              "index" => 0
            }
          ],
          "usageMetadata" => %{
            "promptTokenCount" => 40,
            "candidatesTokenCount" => 8,
            "totalTokenCount" => 48
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(json_response))
      end
    )

    calculator_function = %LlmComposer.Function{
      mf: {__MODULE__, :calculator},
      name: "calculator",
      description: "Calculator function",
      schema: %{
        "type" => "object",
        "properties" => %{"expression" => %{"type" => "string"}},
        "required" => ["expression"]
      }
    }

    settings = %Settings{
      providers: [
        {LlmComposer.Providers.Google,
         [
           model: "gemini-2.5-flash",
           api_key: "test-key",
           url: "http://localhost:#{bypass.port}/v1beta/models/"
         ]}
      ],
      functions: [calculator_function],
      # Disabled
      auto_exec_functions: false,
      system_prompt: "You are a helpful assistant"
    }

    {:ok, response} = LlmComposer.simple_chat(settings, "What is 1 + 1?")

    assert response.actions != []
    assert length(response.actions) == 1
    [actions_list] = response.actions
    assert length(actions_list) == 1
    action = hd(actions_list)
    assert action.name == "calculator"
    assert action.arguments == %{"expression" => "1 + 1"}
    # Not executed
    assert action.result == nil
  end

  test "maybe_exec_functions executes functions and returns completion" do
    fcall = %LlmComposer.FunctionCall{
      type: "function",
      id: "call_1",
      name: "calculator",
      arguments: %{"expression" => "2 + 3"}
    }

    functions = [
      %LlmComposer.Function{
        mf: {__MODULE__, :calculator},
        name: "calculator",
        description: "Calculator function",
        schema: %{"type" => "object"}
      }
    ]

    res = %LlmComposer.LlmResponse{actions: [[fcall]], main_response: nil}

    {:completion, ^res, results} = LlmComposer.Helpers.maybe_exec_functions(res, functions)

    assert length(results) == 1
    assert hd(results).result == 5
  end

  test "maybe_complete_chat builds assistant message from original and serializes results" do
    # Prepare an old response that contains metadata.original with tool_calls (simulating OpenAI/OpenRouter)
    original = %{"tool_calls" => [%{"id" => "call_1"}]}
    old_main = LlmComposer.Message.new(:assistant, "previous", %{original: original})
    oldres = %LlmComposer.LlmResponse{main_response: old_main}

    # Prepare function call results with different result types
    res_map = %LlmComposer.FunctionCall{name: "m1", result: %{"a" => 1}}
    res_bin = %LlmComposer.FunctionCall{name: "m2", result: "a binary"}
    res_other = %LlmComposer.FunctionCall{name: "m3", result: 123}

    messages = [LlmComposer.Message.new(:user, "hi")]

    run_completion = fn new_messages ->
      # Should include assistant message with original preserved and nil content
      assert Enum.any?(new_messages, fn m ->
               m.type == :assistant and m.content == nil and
                 Map.get(m.metadata, :original) == original
             end)

      # Should include function_result messages with serialized contents
      frs = Enum.filter(new_messages, fn m -> m.type == :function_result end)
      assert length(frs) == 3

      [f1, f2, f3] = frs
      assert f1.content == Jason.encode!(%{"a" => 1})
      assert f2.content == "a binary"
      assert f3.content == "123"

      {:ok, :done}
    end

    assert LlmComposer.Helpers.maybe_complete_chat(
             {:completion, oldres, [res_map, res_bin, res_other]},
             messages,
             run_completion
           ) == {:ok, :done}
  end

  test "maybe_complete_chat falls back to main_response when original does not include tool_calls or parts" do
    old_main = LlmComposer.Message.new(:assistant, "prev content", %{})
    oldres = %LlmComposer.LlmResponse{main_response: old_main}

    res = %LlmComposer.FunctionCall{name: "m1", result: "ok"}
    messages = [LlmComposer.Message.new(:user, "hello")]

    run_completion = fn new_messages ->
      # Assistant message should be the previous main_response
      assert Enum.any?(new_messages, fn m ->
               m.type == :assistant and m.content == "prev content"
             end)

      {:ok, :done}
    end

    assert LlmComposer.Helpers.maybe_complete_chat(
             {:completion, oldres, [res]},
             messages,
             run_completion
           ) == {:ok, :done}
  end

  # Test helper functions
  @spec calculator(map()) :: integer() | float() | {:error, String.t()}
  def calculator(%{"expression" => expression}) do
    # Simple calculator for testing
    case expression do
      "2 + 3" -> 5
      "10 / 2" -> 5.0
      "5 * 3" -> 15
      "1 + 1" -> 2
      "2 * 3" -> 6
      _ -> {:error, "Unsupported expression"}
    end
  end

  defp endpoint_url(port), do: "http://localhost:#{port}/"
end
