defimpl LlmComposer.ProviderStreamChunk, for: LlmComposer.ProviderStreamChunk.OpenAI do
  def to_stream_chunk(%{chunk: chunk}, _opts) do
    LlmComposer.ProviderStreamChunk.Parser.OpenAIRouter.parse(chunk, :open_ai, [])
  end
end

defimpl LlmComposer.ProviderStreamChunk, for: LlmComposer.ProviderStreamChunk.OpenRouter do
  def to_stream_chunk(%{chunk: chunk}, _opts) do
    LlmComposer.ProviderStreamChunk.Parser.OpenAIRouter.parse(chunk, :open_router, [])
  end
end

defimpl LlmComposer.ProviderStreamChunk, for: LlmComposer.ProviderStreamChunk.Google do
  def to_stream_chunk(%{chunk: chunk}, _opts) do
    LlmComposer.ProviderStreamChunk.Parser.Google.parse(chunk, :google, [])
  end
end

defimpl LlmComposer.ProviderStreamChunk, for: LlmComposer.ProviderStreamChunk.Ollama do
  def to_stream_chunk(%{chunk: chunk}, _opts) do
    LlmComposer.ProviderStreamChunk.Parser.Ollama.parse(chunk, :ollama, [])
  end
end
