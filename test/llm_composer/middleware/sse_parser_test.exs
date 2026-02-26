defmodule LlmComposer.Middleware.SSEParserTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Middleware.SSEParser

  describe "new/0" do
    test "returns parser with empty buffer" do
      parser = SSEParser.new()

      assert %SSEParser{buffer: "", events: []} = parser
    end
  end

  describe "parse_chunk/2" do
    test "parses complete single event" do
      parser = SSEParser.new()
      chunk = "data: {\"foo\":1}\n\n"

      assert {:ok, [event], new_parser} = SSEParser.parse_chunk(chunk, parser)

      assert event.data == "{\"foo\":1}"
      assert new_parser.buffer == ""
    end

    test "parses multiple events in one chunk" do
      parser = SSEParser.new()
      chunk = "data: a\n\ndata: b\n\n"

      assert {:ok, [event_a, event_b], new_parser} = SSEParser.parse_chunk(chunk, parser)

      assert event_a.data == "a"
      assert event_b.data == "b"
      assert new_parser.buffer == ""
    end

    test "buffers partial chunk - first chunk incomplete" do
      parser = SSEParser.new()
      chunk1 = "data: {"

      assert {:ok, [], parser1} = SSEParser.parse_chunk(chunk1, parser)
      assert parser1.buffer == "data: {"
    end

    test "buffers partial chunk - second chunk completes event" do
      parser = SSEParser.new()
      {:ok, [], parser1} = SSEParser.parse_chunk("data: {", parser)
      chunk2 = "\"foo\":1}\n\n"

      assert {:ok, [event], parser2} = SSEParser.parse_chunk(chunk2, parser1)

      assert event.data == "{\"foo\":1}"
      assert parser2.buffer == ""
    end

    test "handles chunk that would crash Tesla - partial JSON only" do
      parser = SSEParser.new()
      # Google/Vertex can send "{" as first chunk; Tesla.Middleware.SSE would FunctionClauseError
      chunk = "{"

      assert {:ok, [], _parser} = SSEParser.parse_chunk(chunk, parser)
    end

    test "ignores comment lines" do
      parser = SSEParser.new()
      chunk = ": this is a comment\ndata: hi\n\n"

      assert {:ok, [event], _} = SSEParser.parse_chunk(chunk, parser)
      assert event.data == "hi"
    end

    test "parses event with id and event type" do
      parser = SSEParser.new()
      chunk = "event: message\nid: 123\ndata: payload\n\n"

      assert {:ok, [event], _} = SSEParser.parse_chunk(chunk, parser)

      assert event.data == "payload"
      assert event.event == "message"
      assert event.id == "123"
    end
  end

  describe "finalize/1" do
    test "returns empty list when buffer is empty" do
      parser = SSEParser.new()

      assert {:ok, []} = SSEParser.finalize(parser)
    end

    test "parses remaining buffer as last event" do
      parser = %SSEParser{SSEParser.new() | buffer: "data: trailing\n\n"}

      assert {:ok, [event]} = SSEParser.finalize(parser)
      assert event.data == "trailing"
    end

    test "returns empty for buffer with no data lines" do
      parser = %SSEParser{SSEParser.new() | buffer: ": comment only\n\n"}

      assert {:ok, []} = SSEParser.finalize(parser)
    end
  end
end
