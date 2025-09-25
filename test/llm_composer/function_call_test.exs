defmodule LlmComposer.FunctionCallTest do
  use ExUnit.Case, async: true

  alias LlmComposer.FunctionCall

  describe "struct creation" do
    test "creates function call with default values" do
      call = %FunctionCall{}

      assert call.arguments == nil
      assert call.id == nil
      assert call.metadata == nil
      assert call.name == nil
      assert call.result == nil
      assert call.type == nil
    end

    test "creates function call with all fields" do
      call = %FunctionCall{
        arguments: "{\"param\": \"value\"}",
        id: "call_123",
        metadata: %{timestamp: "2023-01-01"},
        name: "test_function",
        result: {:ok, "success"},
        type: "function"
      }

      assert call.arguments == "{\"param\": \"value\"}"
      assert call.id == "call_123"
      assert call.metadata == %{timestamp: "2023-01-01"}
      assert call.name == "test_function"
      assert call.result == {:ok, "success"}
      assert call.type == "function"
    end

    test "creates minimal function call for execution" do
      call = %FunctionCall{
        name: "calculator",
        arguments: "{\"expression\": \"2 + 2\"}"
      }

      assert call.name == "calculator"
      assert call.arguments == "{\"expression\": \"2 + 2\"}"
      assert call.id == nil
      assert call.result == nil
    end

    test "creates function call with execution result" do
      call = %FunctionCall{
        name: "get_weather",
        arguments: "{\"city\": \"Madrid\"}",
        result: {:ok, %{temperature: 25, condition: "sunny"}},
        type: "function"
      }

      assert call.name == "get_weather"
      assert call.result == {:ok, %{temperature: 25, condition: "sunny"}}
    end
  end

  describe "type specifications" do
    test "accepts various result types" do
      # Success tuple
      call1 = %FunctionCall{result: {:ok, "data"}}
      assert call1.result == {:ok, "data"}

      # Error tuple
      call2 = %FunctionCall{result: {:error, "failed"}}
      assert call2.result == {:error, "failed"}

      # Raw data
      call3 = %FunctionCall{result: %{key: "value"}}
      assert call3.result == %{key: "value"}

      # String result
      call4 = %FunctionCall{result: "plain text"}
      assert call4.result == "plain text"

      # Nil result
      call5 = %FunctionCall{result: nil}
      assert call5.result == nil
    end

    test "accepts various metadata types" do
      # Map metadata
      call1 = %FunctionCall{metadata: %{source: "openai", timestamp: 123_456}}
      assert call1.metadata == %{source: "openai", timestamp: 123_456}

      # Keyword list metadata
      call2 = %FunctionCall{metadata: [provider: :openai, model: "gpt-4"]}
      assert call2.metadata == [provider: :openai, model: "gpt-4"]

      # Nil metadata
      call3 = %FunctionCall{metadata: nil}
      assert call3.metadata == nil
    end
  end
end
