defmodule LlmComposer.ProviderResponse.Google do
  @moduledoc false

  use LlmComposer.ProviderResponse.Struct,
    parser: LlmComposer.ProviderResponse.Parser.Google,
    provider: :google
end
