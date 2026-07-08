defmodule LlmComposer.ProviderResponse.Parser.BedrockTest do
  use ExUnit.Case, async: true

  alias LlmComposer.ProviderResponse.Parser.Bedrock

  # Guarantees :assistant exists as an atom regardless of test run/load order,
  # since `parse/3` derives it from a string via `String.to_existing_atom/1`.
  setup_all do
    _ = :assistant
    :ok
  end

  describe "parse/3 with :tool_use structured output strategy" do
    test "unwraps the structured_response tool call into main_response content" do
      response = %{
        "output" => %{
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "toolUse" => %{
                  "toolUseId" => "call_1",
                  "name" => "structured_response",
                  "input" => %{"answer" => "42"}
                }
              }
            ]
          }
        },
        "usage" => %{"inputTokens" => 10, "outputTokens" => 5}
      }

      opts = [response_schema: %{"type" => "object"}, structured_output_strategy: :tool_use]

      assert {:ok, llm_response} = Bedrock.parse({:ok, %{response: response}}, :bedrock, opts)
      assert llm_response.main_response.content == ~s({"answer":"42"})
      assert llm_response.main_response.function_calls == nil
    end

    test "leaves other tool calls untouched when structured_response is not called" do
      response = %{
        "output" => %{
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "toolUse" => %{
                  "toolUseId" => "call_1",
                  "name" => "some_other_tool",
                  "input" => %{"foo" => "bar"}
                }
              }
            ]
          }
        },
        "usage" => %{"inputTokens" => 10, "outputTokens" => 5}
      }

      opts = [response_schema: %{"type" => "object"}, structured_output_strategy: :tool_use]

      assert {:ok, llm_response} = Bedrock.parse({:ok, %{response: response}}, :bedrock, opts)
      assert llm_response.main_response.content == nil
      assert [%{name: "some_other_tool"}] = llm_response.main_response.function_calls
    end

    test "keeps remaining tool calls alongside the unwrapped structured response" do
      response = %{
        "output" => %{
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "toolUse" => %{
                  "toolUseId" => "call_1",
                  "name" => "some_other_tool",
                  "input" => %{"foo" => "bar"}
                }
              },
              %{
                "toolUse" => %{
                  "toolUseId" => "call_2",
                  "name" => "structured_response",
                  "input" => %{"answer" => "42"}
                }
              }
            ]
          }
        },
        "usage" => %{"inputTokens" => 10, "outputTokens" => 5}
      }

      opts = [response_schema: %{"type" => "object"}, structured_output_strategy: :tool_use]

      assert {:ok, llm_response} = Bedrock.parse({:ok, %{response: response}}, :bedrock, opts)
      assert llm_response.main_response.content == ~s({"answer":"42"})
      assert [%{name: "some_other_tool"}] = llm_response.main_response.function_calls
    end

    test "falls back to plain text extraction without the tool_use strategy" do
      response = %{
        "output" => %{
          "message" => %{
            "role" => "assistant",
            "content" => [%{"text" => "hello"}]
          }
        },
        "usage" => %{"inputTokens" => 10, "outputTokens" => 5}
      }

      opts = [response_schema: %{"type" => "object"}]

      assert {:ok, llm_response} = Bedrock.parse({:ok, %{response: response}}, :bedrock, opts)
      assert llm_response.main_response.content == "hello"
    end
  end
end
