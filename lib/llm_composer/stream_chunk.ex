defmodule LlmComposer.StreamChunk do
  @moduledoc """
  Normalized representation of a streaming chunk emitted by any provider.

  - `:provider` identifies the upstream provider (:open_ai | :open_router | :google | :ollama | :bedrock)
  - `:type` categorizes the event (`:text_delta`, `:tool_call_delta`, `:usage`, `:done`, `:error`, `:unknown`)
  - `:text` is the accumulated text delta (if any)
  - `:tool_call` keeps normalized tool/function call fragments
  - `:usage` stores the token usage payload when available
  - `:cost_info` can surface cost data on the final chunk
  - `:metadata` holds provider-specific attributes (finish reason, role, etc.)
  - `:raw` retains the original decoded payload for inspection.
  """

  alias LlmComposer.CostInfo

  @type usage() ::
          %{
            input_tokens: non_neg_integer() | nil,
            output_tokens: non_neg_integer() | nil,
            total_tokens: non_neg_integer() | nil
          }

  @type t() :: %__MODULE__{
          provider: atom(),
          type: :text_delta | :tool_call_delta | :usage | :done | :error | :unknown,
          text: String.t() | nil,
          tool_call: map() | nil,
          usage: usage() | nil,
          cost_info: CostInfo.t() | nil,
          metadata: map(),
          raw: term()
        }

  defstruct [
    :provider,
    :type,
    :text,
    :tool_call,
    :usage,
    :cost_info,
    :raw,
    metadata: %{}
  ]
end
