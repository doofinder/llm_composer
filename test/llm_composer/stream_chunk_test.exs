defmodule LlmComposer.StreamChunkTest do
  use ExUnit.Case, async: true

  alias LlmComposer.StreamChunk

  describe "parse_stream_response/2" do
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
