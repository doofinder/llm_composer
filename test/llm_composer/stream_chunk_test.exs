defmodule LlmComposer.StreamChunkTest do
  use ExUnit.Case, async: true

  alias LlmComposer.StreamChunk

  describe "parse_stream_response/2" do
    test "OpenAI tool_call delta is classified as :tool_call_delta" do
      data =
        ~s(data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"get_weather","arguments":""}}]},"index":0,"finish_reason":null}]})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai)
        |> Enum.to_list()

      assert %StreamChunk{provider: :open_ai, type: :tool_call_delta} = chunk
      assert is_list(chunk.tool_call)
      assert [%{"function" => %{"name" => "get_weather"}}] = chunk.tool_call
    end

    test "OpenAI tool_call argument delta chunk is :tool_call_delta" do
      data =
        ~s(data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"loc"}}]},"index":0,"finish_reason":null}]})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai)
        |> Enum.to_list()

      assert %StreamChunk{type: :tool_call_delta} = chunk
      assert [%{"function" => %{"arguments" => "{\"loc"}}] = chunk.tool_call
    end

    test "opts passed to parse_stream_response/3 are forwarded to parser" do
      # Verifies the opts pipeline is not dropped (struct.ex bug).
      # The parser ignores opts today, but this confirms no crash and correct
      # output shape when opts are non-empty.
      data = ~s(data: {"choices":[{"delta":{"content":"Hi"},"index":0,"finish_reason":null}]})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai, some_opt: true)
        |> Enum.to_list()

      assert %StreamChunk{type: :text_delta, text: "Hi"} = chunk
    end

    test "maps OpenAI chunks to text deltas" do
      data = ~s(data: {"choices":[{"delta":{"content":"Hi"},"index":0,"finish_reason":null}]})
      stream = [data, "[DONE]"]

      [chunk] =
        stream
        |> LlmComposer.parse_stream_response(:open_ai)
        |> Enum.to_list()

      assert %StreamChunk{provider: :open_ai, type: :text_delta, text: "Hi"} = chunk
    end

    test "OpenAI final chunk becomes :done" do
      data = ~s(data: {"choices":[{"delta":{},"index":0,"finish_reason":"stop"}]})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai)
        |> Enum.to_list()

      assert %StreamChunk{type: :done, metadata: %{finish_reason: "stop"}} = chunk
    end

    test "OpenAI usage-only chunk becomes :usage" do
      data = ~s(data: {"usage":{"prompt_tokens":12,"completion_tokens":7,"total_tokens":19}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai)
        |> Enum.to_list()

      assert %StreamChunk{
               provider: :open_ai,
               type: :usage,
               usage: %{input_tokens: 12, output_tokens: 7, total_tokens: 19}
             } = chunk
    end

    test "OpenAI usage-only chunk includes cached tokens, reasoning tokens, and cost info" do
      data =
        ~s(data: {"model":"gpt-4o-mini","usage":{"prompt_tokens":12,"completion_tokens":7,"total_tokens":19,"prompt_tokens_details":{"cached_tokens":4},"completion_tokens_details":{"reasoning_tokens":3}}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(
          :open_ai,
          track_costs: true,
          input_price_per_million: "1.0",
          cache_read_price_per_million: "0.5",
          output_price_per_million: "2.0"
        )
        |> Enum.to_list()

      assert %StreamChunk{
               provider: :open_ai,
               type: :usage,
               usage: %{
                 input_tokens: 12,
                 output_tokens: 7,
                 total_tokens: 19,
                 cached_tokens: 4,
                 reasoning_tokens: 3
               }
             } = chunk

      assert chunk.cost_info.provider_model == "gpt-4o-mini"
      assert chunk.cost_info.cached_tokens == 4
    end

    test "OpenAI reasoning-only chunk becomes :reasoning_delta" do
      data =
        ~s(data: {"choices":[{"delta":{"content":"","reasoning":"Let me think","reasoning_details":[{"type":"reasoning.text","text":"Let me think"}]},"index":0,"finish_reason":null}]})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai)
        |> Enum.to_list()

      assert %StreamChunk{
               provider: :open_ai,
               type: :reasoning_delta,
               reasoning: "Let me think",
               reasoning_details: [%{"text" => "Let me think"}]
             } = chunk
    end

    test "OpenAI mixed text and reasoning chunk stays a text delta" do
      data =
        ~s(data: {"choices":[{"delta":{"content":"Answer","reasoning":"Let me think","reasoning_details":[{"type":"reasoning.text","text":"Let me think"}]},"index":0,"finish_reason":null}]})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai)
        |> Enum.to_list()

      assert %StreamChunk{
               provider: :open_ai,
               type: :text_delta,
               text: "Answer",
               reasoning: "Let me think",
               reasoning_details: [%{"text" => "Let me think"}]
             } = chunk
    end

    test "Google chunk exposes usage and text" do
      data =
        ~s(data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Yo"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":3,"totalTokenCount":8}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:google)
        |> Enum.to_list()

      assert %StreamChunk{
               provider: :google,
               type: :done,
               text: "Yo",
               usage: %{input_tokens: 5, output_tokens: 3, total_tokens: 8}
             } = chunk
    end

    test "Google chunk with functionCall becomes :tool_call_delta" do
      data =
        ~s(data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"http_client","args":{"method":"GET","url":"https://example.com"}}}]}}]})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:google)
        |> Enum.to_list()

      assert %StreamChunk{
               provider: :google,
               type: :tool_call_delta,
               text: nil,
               tool_call: [%LlmComposer.FunctionCall{name: "http_client"}]
             } = chunk
    end

    test "Google done chunk with functionCall still becomes :done" do
      data =
        ~s(data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"http_client","args":{}}}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"totalTokenCount":15}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:google)
        |> Enum.to_list()

      assert %StreamChunk{provider: :google, type: :done} = chunk
    end

    test "Google done chunk maps thoughtsTokenCount to reasoning_tokens" do
      data =
        ~s(data: {"candidates":[{"content":{"role":"model","parts":[{"text":""}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":147,"candidatesTokenCount":151,"totalTokenCount":841,"thoughtsTokenCount":543}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:google)
        |> Enum.to_list()

      assert %StreamChunk{
               provider: :google,
               type: :done,
               usage: %{
                 input_tokens: 147,
                 output_tokens: 151,
                 total_tokens: 841,
                 reasoning_tokens: 543
               }
             } = chunk
    end

    test "Google final chunk includes cost info when pricing opts are provided" do
      data =
        ~s(data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Yo"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":3,"totalTokenCount":8}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(
          :google,
          model: "gemini-2.5-flash",
          track_costs: true,
          input_price_per_million: "1.0",
          output_price_per_million: "2.0"
        )
        |> Enum.to_list()

      assert chunk.cost_info.provider_model == "gemini-2.5-flash"
      assert chunk.cost_info.input_tokens == 5
      assert chunk.cost_info.output_tokens == 3
    end
  end

  describe "parse_stream_response/2 - OpenAIResponses" do
    test "response.output_text.delta becomes :text_delta" do
      data = ~s(data: {"type":"response.output_text.delta","delta":"Hello"})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai_responses)
        |> Enum.to_list()

      assert %StreamChunk{provider: :open_ai_responses, type: :text_delta, text: "Hello"} = chunk
    end

    test "response.output_text.delta with empty string is skipped" do
      data = ~s(data: {"type":"response.output_text.delta","delta":""})

      result =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai_responses)
        |> Enum.to_list()

      assert result == []
    end

    test "response.output_item.added with function_call becomes :tool_call_delta started" do
      data =
        ~s(data: {"type":"response.output_item.added","item":{"type":"function_call","name":"calculator","call_id":"call_abc"}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai_responses)
        |> Enum.to_list()

      assert %StreamChunk{provider: :open_ai_responses, type: :tool_call_delta} = chunk
      assert chunk.tool_call["type"] == "function_call_started"
      assert chunk.tool_call["name"] == "calculator"
      assert chunk.tool_call["call_id"] == "call_abc"
    end

    test "response.output_item.added with non-function type is skipped" do
      data =
        ~s(data: {"type":"response.output_item.added","item":{"type":"message"}})

      result =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai_responses)
        |> Enum.to_list()

      assert result == []
    end

    test "response.function_call_arguments.delta becomes :tool_call_delta with args_delta" do
      data =
        ~s(data: {"type":"response.function_call_arguments.delta","call_id":"call_abc","delta":"{\\"expr"})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai_responses)
        |> Enum.to_list()

      assert %StreamChunk{provider: :open_ai_responses, type: :tool_call_delta} = chunk
      assert chunk.tool_call["type"] == "function_call_arguments_delta"
      assert chunk.tool_call["call_id"] == "call_abc"
      assert chunk.tool_call["arguments_delta"] == "{\"expr"
    end

    test "response.completed becomes :done with usage" do
      data =
        ~s(data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai_responses)
        |> Enum.to_list()

      assert %StreamChunk{
               provider: :open_ai_responses,
               type: :done,
               usage: %{input_tokens: 10, output_tokens: 5, total_tokens: 15, cached_tokens: nil},
               metadata: %{finish_reason: "stop"}
             } = chunk
    end

    test "OpenRouter usage-only chunk includes cost info through the shared parser" do
      data =
        ~s(data: {"model":"anthropic/claude-3-haiku:beta","provider":"openrouter","usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15,"completion_tokens_details":{"reasoning_tokens":2}}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(
          :open_router,
          track_costs: true,
          input_price_per_million: "1.0",
          output_price_per_million: "2.0"
        )
        |> Enum.to_list()

      assert chunk.type == :usage
      assert chunk.usage.reasoning_tokens == 2
      assert chunk.cost_info.provider_model == "anthropic/claude-3-haiku:beta"
    end

    test "response.output_item.done with reasoning summary becomes :reasoning_delta" do
      data =
        ~s(data: {"type":"response.output_item.done","item":{"type":"reasoning","summary":[{"type":"summary_text","text":"Condensed reasoning"}]}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai_responses)
        |> Enum.to_list()

      assert %StreamChunk{
               provider: :open_ai_responses,
               type: :reasoning_delta,
               reasoning: "Condensed reasoning",
               reasoning_details: [%{"text" => "Condensed reasoning"}]
             } = chunk
    end

    test "response.completed carries reasoning summary and usage details" do
      data =
        ~s(data: {"type":"response.completed","response":{"output":[{"type":"reasoning","summary":[{"type":"summary_text","text":"Final summary"}]}],"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15,"output_tokens_details":{"reasoning_tokens":43}}}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai_responses)
        |> Enum.to_list()

      assert %StreamChunk{
               provider: :open_ai_responses,
               type: :done,
               reasoning: "Final summary",
               reasoning_details: [%{"text" => "Final summary"}],
               usage: %{
                 input_tokens: 10,
                 output_tokens: 5,
                 total_tokens: 15,
                 cached_tokens: nil,
                 reasoning_tokens: 43
               }
             } = chunk
    end

    test "response.completed exposes cached prompt tokens in usage" do
      data =
        ~s(data: {"type":"response.completed","response":{"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15,"input_tokens_details":{"cached_tokens":7}}}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai_responses)
        |> Enum.to_list()

      assert %StreamChunk{
               provider: :open_ai_responses,
               type: :done,
               usage: %{
                 input_tokens: 10,
                 output_tokens: 5,
                 total_tokens: 15,
                 cached_tokens: 7,
                 reasoning_tokens: nil
               }
             } = chunk
    end

    test "response.completed includes reasoning token usage and cost info" do
      data =
        ~s(data: {"type":"response.completed","response":{"model":"gpt-5.4-mini","usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15,"input_tokens_details":{"cached_tokens":7},"output_tokens_details":{"reasoning_tokens":43}}}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(
          :open_ai_responses,
          track_costs: true,
          input_price_per_million: "1.0",
          cache_read_price_per_million: "0.25",
          output_price_per_million: "2.0"
        )
        |> Enum.to_list()

      assert chunk.usage.reasoning_tokens == 43
      assert chunk.cost_info.provider_model == "gpt-5.4-mini"
      assert chunk.cost_info.cached_tokens == 7
    end

    test "response.completed with missing usage still becomes :done" do
      data = ~s(data: {"type":"response.completed","response":{}})

      [chunk] =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai_responses)
        |> Enum.to_list()

      assert %StreamChunk{type: :done, usage: nil} = chunk
    end

    test "unknown event types are skipped" do
      data = ~s(data: {"type":"response.in_progress"})

      result =
        [data]
        |> LlmComposer.parse_stream_response(:open_ai_responses)
        |> Enum.to_list()

      assert result == []
    end
  end
end
