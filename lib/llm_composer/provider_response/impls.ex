defimpl LlmComposer.ProviderResponse, for: LlmComposer.ProviderResponse.OpenAI do
  def to_llm_response(%LlmComposer.ProviderResponse.OpenAI{result: result}, opts) do
    LlmComposer.ProviderResponse.Parser.OpenAIRouter.parse(result, :open_ai, opts)
  end
end

defimpl LlmComposer.ProviderResponse, for: LlmComposer.ProviderResponse.OpenRouter do
  def to_llm_response(%LlmComposer.ProviderResponse.OpenRouter{result: result}, opts) do
    LlmComposer.ProviderResponse.Parser.OpenAIRouter.parse(result, :open_router, opts)
  end
end

defimpl LlmComposer.ProviderResponse, for: LlmComposer.ProviderResponse.Google do
  def to_llm_response(%LlmComposer.ProviderResponse.Google{result: result}, opts) do
    LlmComposer.ProviderResponse.Parser.Google.parse(result, :google, opts)
  end
end

defimpl LlmComposer.ProviderResponse, for: LlmComposer.ProviderResponse.Ollama do
  def to_llm_response(%LlmComposer.ProviderResponse.Ollama{result: result}, opts) do
    LlmComposer.ProviderResponse.Parser.Ollama.parse(result, :ollama, opts)
  end
end

defimpl LlmComposer.ProviderResponse, for: LlmComposer.ProviderResponse.Bedrock do
  def to_llm_response(%LlmComposer.ProviderResponse.Bedrock{result: result}, opts) do
    LlmComposer.ProviderResponse.Parser.Bedrock.parse(result, :bedrock, opts)
  end
end
