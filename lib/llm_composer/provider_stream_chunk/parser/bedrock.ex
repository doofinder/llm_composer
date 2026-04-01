defmodule LlmComposer.ProviderStreamChunk.Parser.Bedrock do
  @moduledoc false

  alias LlmComposer.StreamChunk

  @spec parse(map(), atom(), keyword()) :: {:ok, StreamChunk.t()} | :skip
  def parse(%{"delta" => %{"text" => text}} = raw, :bedrock, _opts) do
    {:ok,
     %StreamChunk{
       provider: :bedrock,
       type: :text_delta,
       text: text,
       metadata: %{},
       raw: raw
     }}
  end

  def parse(%{"stopReason" => reason} = raw, :bedrock, _opts) do
    {:ok,
     %StreamChunk{
       provider: :bedrock,
       type: :done,
       metadata: %{finish_reason: reason},
       raw: raw
     }}
  end

  def parse(%{"usage" => usage} = raw, :bedrock, _opts) do
    {:ok,
     %StreamChunk{
       provider: :bedrock,
       type: :usage,
       usage: %{
         input_tokens: usage["inputTokens"],
         output_tokens: usage["outputTokens"],
         total_tokens: usage["totalTokens"],
         cached_tokens: nil,
         reasoning_tokens: nil
       },
       metadata: %{},
       raw: raw
     }}
  end

  def parse(_raw, :bedrock, _opts), do: :skip
end
