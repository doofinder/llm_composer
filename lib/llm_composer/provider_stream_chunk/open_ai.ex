defmodule LlmComposer.ProviderStreamChunk.OpenAI do
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
end
