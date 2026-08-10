defmodule LlmComposer.ProviderResponse.TensorX do
  @moduledoc false

  use LlmComposer.ProviderResponse.Struct,
    parser: LlmComposer.ProviderResponse.Parser.OpenAI,
    provider: :tensorx
end
