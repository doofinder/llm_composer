defmodule LlmComposer.Agent.StreamCollectorTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Agent.StreamCollector
  alias LlmComposer.CostInfo
  alias LlmComposer.FunctionCall
  alias LlmComposer.LlmResponse
  alias LlmComposer.StreamChunk

  describe "OpenAI tool-call reassembly" do
    test "merges fragmented arguments by index into a single FunctionCall" do
      chunks = [
        tool_chunk([
          %{
            "index" => 0,
            "id" => "call_1",
            "type" => "function",
            "function" => %{"name" => "get_weather", "arguments" => ""}
          }
        ]),
        tool_chunk([%{"index" => 0, "function" => %{"arguments" => "{\"loc"}}]),
        tool_chunk([%{"index" => 0, "function" => %{"arguments" => "ation\":\"Paris\"}"}}])
      ]

      collector = collect(:open_ai, chunks)

      assert StreamCollector.tool_turn?(collector)

      assert [%FunctionCall{id: "call_1", name: "get_weather", arguments: args, type: "function"}] =
               StreamCollector.to_function_calls(collector)

      assert args == "{\"location\":\"Paris\"}"
    end

    test "keeps multiple parallel tool calls separated by index" do
      chunks = [
        tool_chunk([
          %{
            "index" => 0,
            "id" => "a",
            "type" => "function",
            "function" => %{"name" => "f", "arguments" => "{\"x\":1}"}
          },
          %{
            "index" => 1,
            "id" => "b",
            "type" => "function",
            "function" => %{"name" => "g", "arguments" => "{\"y\":2}"}
          }
        ])
      ]

      collector = collect(:open_ai, chunks)

      assert [%FunctionCall{id: "a", name: "f"}, %FunctionCall{id: "b", name: "g"}] =
               StreamCollector.to_function_calls(collector)
    end
  end

  describe "Google tool-call collection" do
    test "collects already-complete FunctionCall structs" do
      call = %FunctionCall{
        id: "http_client",
        name: "http_client",
        arguments: "{}",
        type: "function"
      }

      chunk = %StreamChunk{provider: :google, type: :tool_call_delta, tool_calls: [call]}

      collector = collect(:google, [chunk])

      assert StreamCollector.tool_turn?(collector)
      assert StreamCollector.to_function_calls(collector) == [call]
    end
  end

  describe "to_llm_response/1" do
    test "builds a final assistant response from text and usage" do
      collector =
        collect(:open_ai, [
          text_chunk("Hello "),
          text_chunk("world"),
          usage_chunk(%{input_tokens: 10, output_tokens: 4})
        ])

      assert %LlmResponse{
               provider: :open_ai,
               status: :ok,
               input_tokens: 10,
               output_tokens: 4,
               main_response: %{type: :assistant, content: "Hello world", function_calls: []}
             } = StreamCollector.to_llm_response(collector)
    end

    test "exposes reassembled tool calls as the response function_calls" do
      collector =
        collect(:open_ai, [
          tool_chunk([
            %{
              "index" => 0,
              "id" => "c",
              "type" => "function",
              "function" => %{"name" => "f", "arguments" => "{}"}
            }
          ])
        ])

      assert [%FunctionCall{name: "f"}] =
               StreamCollector.to_llm_response(collector).main_response.function_calls
    end
  end

  describe "aggregate_cost_infos/1" do
    test "returns nil for an empty list" do
      assert StreamCollector.aggregate_cost_infos([]) == nil
    end

    test "sums tokens and Decimal costs across turns" do
      a = cost_info(10, 5, "0.10")
      b = cost_info(20, 8, "0.20")

      assert %CostInfo{input_tokens: 30, output_tokens: 13, total_tokens: 43, total_cost: total} =
               StreamCollector.aggregate_cost_infos([a, b])

      assert Decimal.equal?(total, Decimal.new("0.30"))
    end
  end

  describe "OpenRouter tool-call reassembly" do
    test "merges fragmented arguments by index (same format as OpenAI)" do
      chunks = [
        %StreamChunk{
          provider: :open_router,
          type: :tool_call_delta,
          tool_calls: [
            %{
              "index" => 0,
              "id" => "call_or_1",
              "type" => "function",
              "function" => %{"name" => "get_weather", "arguments" => ""}
            }
          ]
        },
        %StreamChunk{
          provider: :open_router,
          type: :tool_call_delta,
          tool_calls: [%{"index" => 0, "function" => %{"arguments" => "{\"city\":"}}]
        },
        %StreamChunk{
          provider: :open_router,
          type: :tool_call_delta,
          tool_calls: [%{"index" => 0, "function" => %{"arguments" => "\"Paris\"}"}}]
        }
      ]

      collector = collect(:open_router, chunks)

      assert StreamCollector.tool_turn?(collector)

      assert [
               %FunctionCall{
                 id: "call_or_1",
                 name: "get_weather",
                 arguments: "{\"city\":\"Paris\"}",
                 type: "function"
               }
             ] = StreamCollector.to_function_calls(collector)
    end
  end

  describe "Bedrock tool-call reassembly" do
    test "merges a start chunk and inputJson deltas into a FunctionCall" do
      chunks = [
        %StreamChunk{
          provider: :bedrock,
          type: :tool_call_delta,
          tool_calls: [%{"toolUseId" => "bedrock_1", "name" => "calculator", "inputJson" => ""}]
        },
        %StreamChunk{
          provider: :bedrock,
          type: :tool_call_delta,
          tool_calls: [%{"inputJson" => "{\"expression\":"}]
        },
        %StreamChunk{
          provider: :bedrock,
          type: :tool_call_delta,
          tool_calls: [%{"inputJson" => "\"2 + 3\"}"}]
        }
      ]

      collector = collect(:bedrock, chunks)

      assert StreamCollector.tool_turn?(collector)

      assert [
               %FunctionCall{
                 id: "bedrock_1",
                 name: "calculator",
                 arguments: "{\"expression\":\"2 + 3\"}",
                 type: "function"
               }
             ] = StreamCollector.to_function_calls(collector)
    end

    test "preserves insertion order for multiple sequential tool calls" do
      chunks = [
        %StreamChunk{
          provider: :bedrock,
          type: :tool_call_delta,
          tool_calls: [%{"toolUseId" => "id_a", "name" => "tool_a", "inputJson" => ""}]
        },
        %StreamChunk{
          provider: :bedrock,
          type: :tool_call_delta,
          tool_calls: [%{"inputJson" => "{\"x\":1}"}]
        },
        %StreamChunk{
          provider: :bedrock,
          type: :tool_call_delta,
          tool_calls: [%{"toolUseId" => "id_b", "name" => "tool_b", "inputJson" => ""}]
        },
        %StreamChunk{
          provider: :bedrock,
          type: :tool_call_delta,
          tool_calls: [%{"inputJson" => "{\"y\":2}"}]
        }
      ]

      collector = collect(:bedrock, chunks)

      assert [
               %FunctionCall{id: "id_a", name: "tool_a", arguments: "{\"x\":1}"},
               %FunctionCall{id: "id_b", name: "tool_b", arguments: "{\"y\":2}"}
             ] = StreamCollector.to_function_calls(collector)
    end

    test "to_llm_response/1 exposes assembled Bedrock tool calls" do
      chunks = [
        %StreamChunk{
          provider: :bedrock,
          type: :tool_call_delta,
          tool_calls: [%{"toolUseId" => "bid_1", "name" => "lookup", "inputJson" => "{}"}]
        },
        %StreamChunk{
          provider: :bedrock,
          type: :usage,
          usage: %{input_tokens: 8, output_tokens: 3}
        }
      ]

      collector = collect(:bedrock, chunks)

      assert %LlmResponse{
               provider: :bedrock,
               status: :ok,
               input_tokens: 8,
               output_tokens: 3,
               main_response: %{
                 type: :assistant,
                 function_calls: [%FunctionCall{id: "bid_1", name: "lookup", arguments: "{}"}]
               }
             } = StreamCollector.to_llm_response(collector)
    end
  end

  test "new/1 raises for unsupported providers" do
    assert_raise ArgumentError, fn -> StreamCollector.new(:unknown_provider) end
  end

  # --- Helpers ---

  defp collect(provider, chunks) do
    Enum.reduce(chunks, StreamCollector.new(provider), &StreamCollector.add(&2, &1))
  end

  defp tool_chunk(tool_calls) do
    %StreamChunk{provider: :open_ai, type: :tool_call_delta, tool_calls: tool_calls}
  end

  defp text_chunk(text) do
    %StreamChunk{provider: :open_ai, type: :text_delta, text: text}
  end

  defp usage_chunk(usage) do
    %StreamChunk{provider: :open_ai, type: :usage, usage: usage}
  end

  defp cost_info(input_tokens, output_tokens, total_cost) do
    %CostInfo{
      provider_name: :open_ai,
      provider_model: "gpt-4.1-mini",
      currency: "USD",
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: input_tokens + output_tokens,
      cached_tokens: 0,
      total_cost: Decimal.new(total_cost)
    }
  end
end
