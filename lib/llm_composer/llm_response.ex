defmodule LlmComposer.LlmResponse do
  @moduledoc """
  Normalized representation of a response coming from any provider.

  Parser modules are responsible for translating provider-specific HTTP results into
  this normalized struct so the rest of the library can stay provider-agnostic.
  """

  alias LlmComposer.CostInfo
  alias LlmComposer.FunctionCall
  alias LlmComposer.Message

  @type provider() :: :open_ai | :open_ai_responses | :ollama | :open_router | :bedrock | :google

  @typedoc """
  Normalized response from any LLM provider.

  - `:status` — `:ok` or `:error`.
  - `:main_response` — the primary assistant `Message.t()`.
  - `:input_tokens` — number of input tokens consumed.
  - `:output_tokens` — number of output tokens generated.
  - `:cached_tokens` — number of tokens served from provider cache.
  - `:reasoning_tokens` — tokens used for internal reasoning (where supported).
  - `:provider` — atom identifying the provider (see `provider/0` type).
  - `:provider_model` — model identifier string as reported by the provider.
  - `:response_id` — provider-assigned response ID, used for multi-turn continuations.
  - `:previous_response` — raw previous response map, used by stateful APIs (e.g. OpenAI Responses).
  - `:stream` — enumerable of `LlmComposer.StreamChunk.t()` when streaming is enabled, otherwise `nil`.
  - `:cost_info` — `CostInfo.t()` with cost breakdown when `:track_costs` is enabled.
  - `:metadata` — arbitrary map for provider-specific extra data.
  - `:raw` — original decoded provider payload, useful for debugging.
  """
  @type t() :: %__MODULE__{
          cached_tokens: non_neg_integer() | nil,
          cost_info: CostInfo.t() | nil,
          input_tokens: non_neg_integer() | nil,
          main_response: Message.t() | nil,
          metadata: map(),
          output_tokens: non_neg_integer() | nil,
          previous_response: map() | nil,
          provider: provider(),
          provider_model: String.t() | nil,
          raw: any(),
          reasoning_tokens: non_neg_integer() | nil,
          response_id: String.t() | nil,
          status: :ok | :error,
          stream: nil | Enumerable.t()
        }

  defstruct [
    :cached_tokens,
    :cost_info,
    :input_tokens,
    :main_response,
    :metadata,
    :output_tokens,
    :previous_response,
    :provider,
    :provider_model,
    :raw,
    :reasoning_tokens,
    :response_id,
    :status,
    :stream
  ]

  @doc """
  Builds an `LlmResponse` struct from an attribute map, defaulting `:metadata` to `%{}`.
  """
  @spec new(map()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) do
    attrs = Map.put_new(attrs, :metadata, %{})
    struct!(__MODULE__, attrs)
  end

  @doc """
  Returns the function calls from the main response message.

  Delegates to `main_response.function_calls` for convenience.
  """
  @spec function_calls(t()) :: [FunctionCall.t()] | nil
  def function_calls(%__MODULE__{main_response: nil}), do: nil
  def function_calls(%__MODULE__{main_response: msg}), do: msg.function_calls
end
