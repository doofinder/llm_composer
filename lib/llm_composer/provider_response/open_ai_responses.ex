defmodule LlmComposer.ProviderResponse.OpenAIResponses do
  @moduledoc false

  use LlmComposer.ProviderResponse.Struct,
    parser: LlmComposer.ProviderResponse.Parser.OpenAI,
    provider: :open_ai_responses
end
