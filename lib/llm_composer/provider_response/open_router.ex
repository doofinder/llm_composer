defmodule LlmComposer.ProviderResponse.OpenRouter do
  @moduledoc false

  use LlmComposer.ProviderResponse.Struct,
    parser: LlmComposer.ProviderResponse.Parser.OpenAI,
    provider: :open_router
end
