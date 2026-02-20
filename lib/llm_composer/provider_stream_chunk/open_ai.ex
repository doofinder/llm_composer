defmodule LlmComposer.ProviderStreamChunk.OpenAI do
  @moduledoc false

  use LlmComposer.ProviderStreamChunk.Struct,
    parser: LlmComposer.ProviderStreamChunk.Parser.OpenAIRouter,
    provider: :open_ai
end
