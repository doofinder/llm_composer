defmodule LlmComposer.AgentTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Agent
  alias LlmComposer.Agent.Result
  alias LlmComposer.Function
  alias LlmComposer.Message
  alias LlmComposer.Providers.OpenAI
  alias LlmComposer.Settings

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  # --- Tool functions invoked by the loop ---

  @spec calculator(map()) :: number()
  def calculator(%{"expression" => expression}) do
    {result, _binding} = Code.eval_string(expression)
    result
  end

  @spec boom(map()) :: no_return()
  def boom(_args), do: raise("kaboom")

  # --- Tests ---

  test "runs a single tool round then returns the final answer", %{bypass: bypass} do
    Bypass.expect(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)

      if has_tool_message?(request) do
        # second turn: tool result fed back -> final answer
        assert tool_result_content(request, "call_1") == "5"
        json(conn, final_response("The result is 5.", 12, 6))
      else
        # first turn: model requests a tool call
        json(
          conn,
          tool_call_response([{"call_1", "calculator", ~s({"expression":"2 + 3"})}], 10, 5)
        )
      end
    end)

    settings = settings(bypass)
    {:ok, %Result{} = result} = Agent.run(settings, "How much is 2 + 3?")

    assert result.iterations == 2
    assert result.response.main_response.content == "The result is 5."

    assert [%{name: "calculator", id: "call_1", result: 5}] = result.function_calls
    assert length(result.cost_infos) == 2
    assert Enum.map(result.cost_infos, & &1.input_tokens) == [10, 12]

    # full conversation: user, assistant-with-tools, tool_result, final assistant
    assert [
             %Message{type: :user},
             %Message{type: :assistant, function_calls: [_ | _]},
             %Message{type: :tool_result},
             %Message{type: :assistant, content: "The result is 5."}
           ] = result.messages
  end

  test "returns immediately when the model needs no tools", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      json(conn, final_response("Hello there!", 7, 3))
    end)

    settings = settings(bypass)
    {:ok, %Result{} = result} = Agent.run(settings, "hi")

    assert result.iterations == 1
    assert result.response.main_response.content == "Hello there!"
    assert result.function_calls == []
  end

  test "returns an error when max_iterations is exceeded", %{bypass: bypass} do
    # always asks for another tool call -> never converges
    Bypass.expect(bypass, "POST", "/chat/completions", fn conn ->
      json(conn, tool_call_response([{"call_x", "calculator", ~s({"expression":"1 + 1"})}], 5, 5))
    end)

    settings = settings(bypass)

    assert {:error, :max_iterations_reached} =
             Agent.run(settings, "loop forever", max_iterations: 2)
  end

  test "feeds tool execution errors back to the model instead of aborting", %{bypass: bypass} do
    Bypass.expect(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)

      if has_tool_message?(request) do
        assert tool_result_content(request, "call_err") =~ "Error: execution failed"
        json(conn, final_response("Sorry, that tool failed.", 9, 4))
      else
        json(conn, tool_call_response([{"call_err", "boom", "{}"}], 8, 3))
      end
    end)

    settings = settings(bypass)
    {:ok, %Result{} = result} = Agent.run(settings, "trigger a failing tool")

    assert result.iterations == 2
    assert result.response.main_response.content == "Sorry, that tool failed."
    assert [%{name: "boom", result: "Error: execution failed (kaboom)"}] = result.function_calls
  end

  test "executes multiple tool calls in parallel preserving order", %{bypass: bypass} do
    Bypass.expect(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)

      if has_tool_message?(request) do
        assert tool_result_content(request, "call_a") == "5"
        assert tool_result_content(request, "call_b") == "20"
        json(conn, final_response("Both done.", 15, 5))
      else
        json(
          conn,
          tool_call_response(
            [
              {"call_a", "calculator", ~s({"expression":"2 + 3"})},
              {"call_b", "calculator", ~s({"expression":"10 * 2"})}
            ],
            12,
            8
          )
        )
      end
    end)

    settings = settings(bypass)

    {:ok, %Result{} = result} =
      Agent.run(settings, "do two calcs", tool_execution: :parallel)

    assert result.iterations == 2
    assert [%{id: "call_a", result: 5}, %{id: "call_b", result: 20}] = result.function_calls
  end

  test "rejects streaming settings without making a request" do
    settings = %Settings{
      providers: [{OpenAI, [model: "gpt-4.1-mini", api_key: "k", url: "http://localhost:0/"]}],
      system_prompt: "You are a helpful assistant",
      stream_response: true
    }

    assert {:error, :streaming_not_supported} = Agent.run(settings, "hi")
  end

  test "emits run telemetry with iteration count", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      json(conn, final_response("done", 4, 2))
    end)

    handler_id = "agent-telemetry-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:llm_composer, :agent, :run, :stop],
      fn _event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_stop, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    settings = settings(bypass)
    {:ok, _result} = Agent.run(settings, "hi")

    assert_receive {:telemetry_stop, measurements, metadata}
    assert measurements.iterations == 1
    assert metadata.status == :ok
  end

  # --- Helpers ---

  defp settings(bypass) do
    %Settings{
      providers: [
        {OpenAI,
         [
           model: "gpt-4.1-mini",
           api_key: "test-key",
           url: endpoint_url(bypass.port),
           functions: [calculator_function(), boom_function()],
           input_price_per_million: "1.0",
           output_price_per_million: "2.0"
         ]}
      ],
      system_prompt: "You are a helpful assistant",
      track_costs: true
    }
  end

  defp calculator_function do
    %Function{
      mf: {__MODULE__, :calculator},
      name: "calculator",
      description: "Evaluate a math expression",
      schema: %{
        "type" => "object",
        "properties" => %{"expression" => %{"type" => "string"}},
        "required" => ["expression"]
      }
    }
  end

  defp boom_function do
    %Function{
      mf: {__MODULE__, :boom},
      name: "boom",
      description: "A tool that always raises",
      schema: %{"type" => "object", "properties" => %{}}
    }
  end

  defp has_tool_message?(%{"messages" => messages}) do
    Enum.any?(messages, &(&1["role"] == "tool"))
  end

  defp tool_result_content(%{"messages" => messages}, tool_call_id) do
    Enum.find_value(messages, fn
      %{"role" => "tool", "tool_call_id" => ^tool_call_id, "content" => content} -> content
      _message -> nil
    end)
  end

  defp tool_call_response(calls, prompt_tokens, completion_tokens) do
    tool_calls =
      Enum.map(calls, fn {id, name, arguments} ->
        %{
          "id" => id,
          "type" => "function",
          "function" => %{"name" => name, "arguments" => arguments}
        }
      end)

    %{
      "id" => "chatcmpl-tool",
      "object" => "chat.completion",
      "model" => "gpt-4.1-mini",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{"role" => "assistant", "content" => nil, "tool_calls" => tool_calls},
          "finish_reason" => "tool_calls"
        }
      ],
      "usage" => %{"prompt_tokens" => prompt_tokens, "completion_tokens" => completion_tokens}
    }
  end

  defp final_response(content, prompt_tokens, completion_tokens) do
    %{
      "id" => "chatcmpl-final",
      "object" => "chat.completion",
      "model" => "gpt-4.1-mini",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{"role" => "assistant", "content" => content},
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{"prompt_tokens" => prompt_tokens, "completion_tokens" => completion_tokens}
    }
  end

  defp json(conn, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.resp(200, Jason.encode!(body))
  end

  defp endpoint_url(port), do: "http://localhost:#{port}/"
end
