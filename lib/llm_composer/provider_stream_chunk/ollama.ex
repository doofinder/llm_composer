defmodule LlmComposer.ProviderStreamChunk.Ollama do
  @moduledoc false

  use LlmComposer.ProviderStreamChunk.Struct,
    parser: LlmComposer.ProviderStreamChunk.Parser.Ollama,
    provider: :ollama
end
