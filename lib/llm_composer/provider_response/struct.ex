defmodule LlmComposer.ProviderResponse.Struct do
  @moduledoc false

  defmacro __using__(opts \\ []) do
    parser = Keyword.fetch!(opts, :parser)
    provider = Keyword.fetch!(opts, :provider)

    quote do
      @moduledoc false

      @type t :: %__MODULE__{
              result: term(),
              opts: keyword()
            }

      defstruct [:result, opts: []]

      @spec new(term(), keyword()) :: t()
      def new(result, opts \\ []) do
        %__MODULE__{result: result, opts: opts}
      end

      defimpl LlmComposer.ProviderResponse do
        @spec to_llm_response(struct(), keyword()) ::
                {:ok, LlmComposer.LlmResponse.t()} | {:error, term()}
        def to_llm_response(%{result: result}, opts) do
          unquote(parser).parse(result, unquote(provider), opts)
        end
      end
    end
  end
end
