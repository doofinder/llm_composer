defmodule LlmComposer.ProviderStreamChunk.TensorX do
  @moduledoc false

  use LlmComposer.ProviderStreamChunk.Struct,
    parser: LlmComposer.ProviderStreamChunk.Parser.OpenAI,
    provider: :tensorx
end
