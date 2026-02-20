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
end
