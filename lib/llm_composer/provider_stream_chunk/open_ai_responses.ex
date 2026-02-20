defmodule LlmComposer.ProviderStreamChunk.OpenAIResponses do
  @moduledoc false

  use LlmComposer.ProviderStreamChunk.Struct,
    parser: LlmComposer.ProviderStreamChunk.Parser.OpenAIResponses,
    provider: :open_ai_responses
end
