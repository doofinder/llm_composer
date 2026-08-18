if Code.ensure_loaded?(ExAws) do
  defmodule LlmComposer.AgentBedrockStreamErrorTest do
    @moduledoc """
    Regression coverage for the Agent boundary rescuing
    `LlmComposer.Providers.Bedrock.HttpClient.StreamError`.

    Drives `LlmComposer.Agent` over a fake `:bedrock` provider whose stream raises the real
    `HttpClient.StreamError` mid-body (mirroring a dropped/stalled Bedrock connection after
    headers already arrived), without going through ExAws/SigV4/AWS event-stream framing —
    none of which have any test infrastructure elsewhere in this repo. This isolates the piece
    that regressed: whether `Agent` converts that raise into the documented terminal `:error`
    chunk instead of crashing `run/3`.
    """

    use ExUnit.Case, async: true

    alias LlmComposer.Agent
    alias LlmComposer.LlmResponse
    alias LlmComposer.Providers.Bedrock.HttpClient
    alias LlmComposer.Settings
    alias LlmComposer.StreamChunk

    defmodule FakeBedrockProvider do
      @moduledoc false
      @behaviour LlmComposer.Provider

      @impl LlmComposer.Provider
      def name, do: :bedrock

      @impl LlmComposer.Provider
      def run(_messages, _system_message, opts) do
        {:ok,
         %LlmResponse{status: :ok, provider: :bedrock, stream: Keyword.fetch!(opts, :stream)}}
      end
    end

    test "a mid-body Bedrock transport failure surfaces as a terminal :error chunk, not a crash" do
      stream =
        Stream.resource(
          fn -> :chunk end,
          fn
            :chunk -> {[Jason.encode!(%{"delta" => %{"text" => "partial"}})], :raise}
            :raise -> raise HttpClient.StreamError, reason: :timeout
          end,
          fn _state -> :ok end
        )

      settings = %Settings{
        providers: [{FakeBedrockProvider, [stream: stream]}],
        stream_response: true
      }

      {:ok, agent_stream} = Agent.run(settings, "hi")

      outcome =
        Enum.reduce(agent_stream, %{text: "", error: nil}, fn
          %StreamChunk{type: :text_delta, text: text}, acc -> %{acc | text: acc.text <> text}
          %StreamChunk{type: :error} = chunk, acc -> %{acc | error: chunk}
          _chunk, acc -> acc
        end)

      assert outcome.text == "partial"

      assert %StreamChunk{type: :error, metadata: %{reason: {:stream_transport_error, :timeout}}} =
               outcome.error
    end
  end
end
