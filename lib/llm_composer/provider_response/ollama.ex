defmodule LlmComposer.ProviderResponse.Ollama do
  @moduledoc false

  use LlmComposer.ProviderResponse.Struct,
    parser: LlmComposer.ProviderResponse.Parser.Ollama,
    provider: :ollama
end
