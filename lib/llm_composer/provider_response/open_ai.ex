defmodule LlmComposer.ProviderResponse.OpenAI do
  @moduledoc false

  use LlmComposer.ProviderResponse.Struct,
    parser: LlmComposer.ProviderResponse.Parser.OpenAIRouter,
    provider: :open_ai
end
