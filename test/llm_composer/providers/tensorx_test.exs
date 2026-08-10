defmodule LlmComposer.Providers.TensorXTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Cache.Ets
  alias LlmComposer.Function
  alias LlmComposer.Providers.TensorX
  alias LlmComposer.Settings

  setup_all do
    Ets.start_link()
    :ok
  end

  setup do
    bypass = Bypass.open()

    {:ok, bypass: bypass}
  end

  test "defaults to the EU-hosted endpoint" do
    assert TensorX.get_base_url() == "https://api.tensorx.ai/v1"
  end

  test "simple chat with 'hi' returns expected response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      assert ["Bearer test-key"] == Plug.Conn.get_req_header(conn, "authorization")
      assert request_data["model"] == "z-ai/glm-5.1"

      messages = request_data["messages"]
      user_message = Enum.find(messages, &(&1["role"] == "user"))
      assert user_message["content"] == "hi"

      system_message = Enum.find(messages, &(&1["role"] == "system"))
      assert system_message["content"] == "You are a helpful assistant"

      response_body = %{
        "id" => "chatcmpl-tensorx-123",
        "object" => "chat.completion",
        "created" => 1_677_628_800,
        "model" => "z-ai/glm-5.1",
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
          "total_tokens" => 28,
          "prompt_tokens_details" => %{"cached_tokens" => 12}
        }
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    settings = settings(bypass)

    {:ok, response} = LlmComposer.simple_chat(settings, "hi")

    assert response.main_response.type == :assistant
    assert response.main_response.content == "Hello! How can I help you today?"
    assert response.input_tokens == 20
    assert response.output_tokens == 8
    assert response.cached_tokens == 12
    assert response.provider == :tensorx
    assert response.provider_model == "z-ai/glm-5.1"
  end

  test "reasoning_content is exposed as reasoning", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      response_body = %{
        "model" => "z-ai/glm-5.1",
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "42",
              "reasoning_content" => "Let me think about it."
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 4,
          "total_tokens" => 14,
          "completion_tokens_details" => %{"reasoning_tokens" => 3}
        }
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response_body))
    end)

    settings = settings(bypass)

    {:ok, response} = LlmComposer.simple_chat(settings, "hi")

    assert response.main_response.reasoning == "Let me think about it."
    assert response.reasoning_tokens == 3
  end

  test "functions are sent as OpenAI-shaped tools", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      assert [
               %{
                 "type" => "function",
                 "function" => %{
                   "name" => "get_weather",
                   "description" => "Get the weather",
                   "parameters" => %{"type" => "object"}
                 }
               }
             ] = request_data["tools"]

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, encoded_ok_body())
    end)

    functions = [
      %Function{
        mf: {__MODULE__, :noop},
        name: "get_weather",
        description: "Get the weather",
        schema: %{"type" => "object"}
      }
    ]

    settings = settings(bypass, functions: functions)

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  test "request_params are merged into the body (thinking switches)", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      assert request_data["chat_template_kwargs"] == %{"thinking" => false}
      assert request_data["temperature"] == 0.2

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, encoded_ok_body())
    end)

    opts = [request_params: %{chat_template_kwargs: %{thinking: false}, temperature: 0.2}]
    settings = settings(bypass, opts)

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  test "response_schema is sent as a json_schema response_format", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      request_data = Jason.decode!(body)

      assert request_data["response_format"] == %{
               "type" => "json_schema",
               "json_schema" => %{
                 "name" => "response",
                 "strict" => true,
                 "schema" => %{"type" => "object"}
               }
             }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, encoded_ok_body())
    end)

    opts = [response_schema: %{"type" => "object"}]
    settings = settings(bypass, opts)

    {:ok, _response} = LlmComposer.simple_chat(settings, "hi")
  end

  test "explicit pricing produces cost info", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, encoded_ok_body())
    end)

    # `Decimal.new/1` only takes integers/binaries, so prices go in as strings.
    opts = [
      input_price_per_million: "1.4",
      output_price_per_million: "4.4"
    ]

    settings = %{settings(bypass, opts) | track_costs: true}

    {:ok, response} = LlmComposer.simple_chat(settings, "hi")

    assert response.cost_info.provider_name == :tensorx
    assert Decimal.equal?(response.cost_info.input_cost, Decimal.new("0.000014"))
  end

  test "missing model returns an error", %{bypass: bypass} do
    settings = %Settings{
      providers: [{TensorX, [api_key: "test-key", url: endpoint_url(bypass.port)]}],
      system_prompt: "You are a helpful assistant"
    }

    assert {:error, :model_not_provided} = LlmComposer.simple_chat(settings, "hi")
  end

  test "non-200 responses are returned as errors", %{bypass: bypass} do
    Bypass.expect(bypass, "POST", "/chat/completions", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(401, Jason.encode!(%{"error" => %{"message" => "invalid api key"}}))
    end)

    settings = settings(bypass)

    assert {:error, %{"error" => %{"message" => "invalid api key"}}} =
             LlmComposer.simple_chat(settings, "hi")
  end

  @spec noop(map()) :: {:ok, String.t()}
  def noop(_args), do: {:ok, "noop"}

  defp encoded_ok_body do
    body = ok_body()
    Jason.encode!(body)
  end

  defp ok_body do
    %{
      "model" => "z-ai/glm-5.1",
      "choices" => [
        %{"message" => %{"role" => "assistant", "content" => "OK"}, "finish_reason" => "stop"}
      ],
      "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 2, "total_tokens" => 12}
    }
  end

  defp settings(bypass, extra_opts \\ []) do
    %Settings{
      providers: [
        {TensorX,
         [
           model: "z-ai/glm-5.1",
           api_key: "test-key",
           url: endpoint_url(bypass.port)
         ] ++ extra_opts}
      ],
      system_prompt: "You are a helpful assistant"
    }
  end

  defp endpoint_url(port), do: "http://localhost:#{port}"
end
