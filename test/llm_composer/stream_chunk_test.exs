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
               usage: %{input_tokens: 10, output_tokens: 5, total_tokens: 15},
               metadata: %{finish_reason: "stop"}
             } = chunk
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
