defmodule LlmComposer.LlmResponse do
  @moduledoc """
  Normalized representation of a response coming from any provider.

  Parser modules are responsible for translating provider-specific HTTP results into
  this normalized struct so the rest of the library can stay provider-agnostic.
  """

  alias LlmComposer.CostInfo
  alias LlmComposer.Message

  @type provider() :: :open_ai | :ollama | :open_router | :bedrock | :google

  @type t() :: %__MODULE__{
          cost_info: CostInfo.t() | nil,
          function_calls: [LlmComposer.FunctionCall.t()] | nil,
          input_tokens: non_neg_integer() | nil,
          main_response: Message.t() | nil,
          metadata: map(),
          output_tokens: non_neg_integer() | nil,
          previous_response: map() | nil,
          provider: provider(),
          raw: any(),
          status: :ok | :error,
          stream: nil | Enumerable.t()
        }

  defstruct [
    :cost_info,
    :function_calls,
    :input_tokens,
    :main_response,
    :metadata,
    :output_tokens,
    :previous_response,
    :provider,
    :raw,
    :status,
    :stream
  ]

  @spec new(map()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) do
    attrs = Map.put_new(attrs, :metadata, %{})
    struct!(__MODULE__, attrs)
  end
end
