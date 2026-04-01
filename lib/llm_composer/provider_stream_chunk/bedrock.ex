defmodule LlmComposer.ProviderStreamChunk.Bedrock do
  @moduledoc false

  use LlmComposer.ProviderStreamChunk.Struct,
    parser: LlmComposer.ProviderStreamChunk.Parser.Bedrock,
    provider: :bedrock
end
