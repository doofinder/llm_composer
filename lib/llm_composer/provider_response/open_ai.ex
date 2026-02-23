defmodule LlmComposer.ProviderResponse.OpenAI do
  @moduledoc false

  use LlmComposer.ProviderResponse.Struct,
    parser: LlmComposer.ProviderResponse.Parser.OpenAI,
    provider: :open_ai
end
