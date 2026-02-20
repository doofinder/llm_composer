defimpl LlmComposer.ProviderStreamChunk, for: LlmComposer.ProviderStreamChunk.OpenAI do
  @spec to_stream_chunk(LlmComposer.ProviderStreamChunk.OpenAI.t(), keyword()) ::
          {:ok, LlmComposer.StreamChunk.t()} | :skip | {:error, term()}
  def to_stream_chunk(%{chunk: chunk}, _opts) do
    LlmComposer.ProviderStreamChunk.Parser.OpenAIRouter.parse(chunk, :open_ai, [])
  end
end

defimpl LlmComposer.ProviderStreamChunk, for: LlmComposer.ProviderStreamChunk.OpenRouter do
  @spec to_stream_chunk(LlmComposer.ProviderStreamChunk.OpenRouter.t(), keyword()) ::
          {:ok, LlmComposer.StreamChunk.t()} | :skip | {:error, term()}
  def to_stream_chunk(%{chunk: chunk}, _opts) do
    LlmComposer.ProviderStreamChunk.Parser.OpenAIRouter.parse(chunk, :open_router, [])
  end
end

defimpl LlmComposer.ProviderStreamChunk, for: LlmComposer.ProviderStreamChunk.Google do
  @spec to_stream_chunk(LlmComposer.ProviderStreamChunk.Google.t(), keyword()) ::
          {:ok, LlmComposer.StreamChunk.t()} | :skip | {:error, term()}
  def to_stream_chunk(%{chunk: chunk}, _opts) do
    LlmComposer.ProviderStreamChunk.Parser.Google.parse(chunk, :google, [])
  end
end

defimpl LlmComposer.ProviderStreamChunk, for: LlmComposer.ProviderStreamChunk.Ollama do
  @spec to_stream_chunk(LlmComposer.ProviderStreamChunk.Ollama.t(), keyword()) ::
          {:ok, LlmComposer.StreamChunk.t()} | :skip | {:error, term()}
  def to_stream_chunk(%{chunk: chunk}, _opts) do
    LlmComposer.ProviderStreamChunk.Parser.Ollama.parse(chunk, :ollama, [])
  end
end
