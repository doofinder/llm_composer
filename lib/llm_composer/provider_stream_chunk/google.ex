defmodule LlmComposer.ProviderStreamChunk.Google do
  @moduledoc false

  use LlmComposer.ProviderStreamChunk.Struct,
    parser: LlmComposer.ProviderStreamChunk.Parser.Google,
    provider: :google
end
