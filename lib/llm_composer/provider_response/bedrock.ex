defmodule LlmComposer.ProviderResponse.Bedrock do
  @moduledoc false

  @type t :: %__MODULE__{
          result: {:ok, map()} | {:error, term()},
          opts: keyword()
        }

  defstruct [:result, opts: []]

  @spec new({:ok, map()} | {:error, term()}, keyword()) :: t()
  def new(result, opts \\ []) do
    %__MODULE__{result: result, opts: opts}
  end
end
