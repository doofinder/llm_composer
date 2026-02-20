defmodule LlmComposer.ProviderStreamChunk.OpenRouter do
  @moduledoc false

  use LlmComposer.ProviderStreamChunk.Struct,
    parser: LlmComposer.ProviderStreamChunk.Parser.OpenAIRouter,
    provider: :open_router
end
