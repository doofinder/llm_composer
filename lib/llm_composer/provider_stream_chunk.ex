defprotocol LlmComposer.ProviderStreamChunk do
  @moduledoc """
  Protocol that normalizes provider stream payloads into `LlmComposer.StreamChunk` structs.

  Each provider must wrap its decoded JSON chunk into a provider-specific struct and implement
  this protocol so the central parser can treat every event uniformly.
  """

  @fallback_to_any true

  @spec to_stream_chunk(t(), keyword()) ::
          {:ok, LlmComposer.StreamChunk.t()} | :skip | {:error, term()}
  def to_stream_chunk(raw, opts)
end

defimpl LlmComposer.ProviderStreamChunk, for: Any do
  def to_stream_chunk(_, _opts) do
    {:error, %{reason: :unsupported_stream_chunk_struct}}
  end
end
