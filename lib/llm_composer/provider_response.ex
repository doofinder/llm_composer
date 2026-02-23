defprotocol LlmComposer.ProviderResponse do
  @moduledoc """
  Protocol that turns provider-specific raw responses into `LlmComposer.LlmResponse` structs.

  Each provider adapter must wrap its raw HTTP result into a dedicated struct and implement
  this protocol. The protocol implementation is responsible for parsing the provider payload,
  extracting function calls, tokens, stream handles, etc., and returning the normalized response.
  """

  @fallback_to_any true

  @spec to_llm_response(t(), keyword()) :: {:ok, LlmComposer.LlmResponse.t()} | {:error, term()}
  def to_llm_response(raw_response, opts)
end

defimpl LlmComposer.ProviderResponse, for: Any do
  def to_llm_response(raw_response, _opts) do
    {:error,
     %{
       reason: :unsupported_response_struct,
       struct: raw_response
     }}
  end
end
