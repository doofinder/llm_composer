defmodule LlmComposer.MessageTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Message

  describe "new/3" do
    test "creates a message with atom type" do
      message = Message.new(:user, "Hello world")

      assert message.type == :user
      assert message.content == "Hello world"
      assert message.metadata == %{}
    end

    test "creates a message with binary type" do
      message = Message.new("user", "Hello world")

      assert message.type == "user"
      assert message.content == "Hello world"
      assert message.metadata == %{}
    end

    test "creates a message with custom metadata" do
      metadata = %{timestamp: "2023-01-01", source: "test"}
      message = Message.new(:assistant, "Response", metadata)

      assert message.type == :assistant
      assert message.content == "Response"
      assert message.metadata == metadata
    end

    test "creates a message with nil content" do
      message = Message.new(:system, nil)

      assert message.type == :system
      assert message.content == nil
      assert message.metadata == %{}
    end

    test "creates a message with list content" do
      content = ["item1", "item2"]
      message = Message.new(:user, content)

      assert message.type == :user
      assert message.content == content
      assert message.metadata == %{}
    end

    test "raises error when type is not atom or binary" do
      assert_raise FunctionClauseError, fn ->
        Message.new(123, "content")
      end
    end

    test "defaults metadata to empty map when not provided" do
      message = Message.new(:user, "content")

      assert message.metadata == %{}
    end
  end

  describe "struct definition" do
    test "has correct enforced keys" do
      # This should fail because :type is required
      assert_raise ArgumentError, fn ->
        struct!(Message, content: "test", metadata: %{})
      end
    end

    test "allows creation with all fields" do
      message =
        struct!(Message,
          type: :user,
          content: "test",
          metadata: %{key: "value"}
        )

      assert message.type == :user
      assert message.content == "test"
      assert message.metadata == %{key: "value"}
    end
  end
end
