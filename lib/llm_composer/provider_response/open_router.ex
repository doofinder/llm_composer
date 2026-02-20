defmodule LlmComposer.ProviderResponse.OpenRouter do
  @moduledoc false

  @type t :: %__MODULE__{
          result: Tesla.Env.result(),
          opts: keyword()
        }

  defstruct [:result, opts: []]

  @spec new(Tesla.Env.result(), keyword()) :: t()
  def new(result, opts \\ []) do
    %__MODULE__{result: result, opts: opts}
  end
end
