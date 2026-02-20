defmodule LlmComposer.ProviderStreamChunk.OpenAI do
  @moduledoc false

  use LlmComposer.ProviderStreamChunk.Struct,
    parser: LlmComposer.ProviderStreamChunk.Parser.OpenAI,
    provider: :open_ai
end
