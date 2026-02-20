defmodule LlmComposer.ProviderStreamChunk.Struct do
  @moduledoc false

  defmacro __using__(opts \\ []) do
    parser = Keyword.fetch!(opts, :parser)
    provider = Keyword.fetch!(opts, :provider)

    quote do
      @moduledoc false

      @type t :: %__MODULE__{
              chunk: map(),
              opts: keyword()
            }

      defstruct [:chunk, opts: []]

      @spec new(map(), keyword()) :: t()
      def new(chunk, opts \\ []) do
        %__MODULE__{chunk: chunk, opts: opts}
      end

      defimpl LlmComposer.ProviderStreamChunk do
        @spec to_stream_chunk(struct(), keyword()) ::
                {:ok, LlmComposer.StreamChunk.t()} | :skip | {:error, term()}
        def to_stream_chunk(%{chunk: chunk, opts: struct_opts}, call_opts) do
          merged_opts = Keyword.merge(struct_opts, call_opts)
          unquote(parser).parse(chunk, unquote(provider), merged_opts)
        end
      end
    end
  end
end
