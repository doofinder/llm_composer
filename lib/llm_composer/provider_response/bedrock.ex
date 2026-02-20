defmodule LlmComposer.ProviderResponse.Bedrock do
  @moduledoc false

  use LlmComposer.ProviderResponse.Struct,
    parser: LlmComposer.ProviderResponse.Parser.Bedrock,
    provider: :bedrock
end
