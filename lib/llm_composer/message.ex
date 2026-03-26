defmodule LlmComposer.Message do
  @moduledoc """
  Module that represents an arbitrary message for any LLM.

  ## Fields

  - `:type` — the role of the message sender (e.g. `:user`, `:assistant`, `:system`, `:tool_result`).
  - `:content` — the text or structured content of the message.
  - `:reasoning` — optional plain-text reasoning string returned by reasoning models.
    Primarily used with OpenRouter: when an assistant message is included in a follow-up
    request, this field is forwarded so the model can continue from where it left off.
  - `:reasoning_details` — optional list of reasoning detail objects (maps) returned by
    reasoning models. Use this instead of (or alongside) `:reasoning` when the provider
    returns structured reasoning blocks (e.g. encrypted or summarised thinking blocks).
    Like `:reasoning`, this field is forwarded by the OpenRouter provider on resend.
  - `:function_calls` — optional list of `LlmComposer.FunctionCall` structs returned by the
    model when it requests tool execution. Set by parsers on assistant messages.
  - `:metadata` — arbitrary map for provider-specific data (e.g. original raw response).
  """

  @type t :: %__MODULE__{
          type: binary() | atom(),
          content: binary() | list() | nil,
          function_calls: [LlmComposer.FunctionCall.t()] | nil,
          reasoning: binary() | nil,
          reasoning_details: list() | nil,
          metadata: map()
        }

  @enforce_keys [:type]
  defstruct [:type, :content, :function_calls, :reasoning, :reasoning_details, :metadata]

  @doc """
  Creates a new message struct with a given type and content.
  """
  @spec new(type :: binary() | atom(), content :: binary() | list() | nil, metadata :: map()) ::
          t()
  def new(type, content, metadata \\ %{})
      when is_binary(type) or is_atom(type) do
    %__MODULE__{type: type, content: content, metadata: metadata}
  end
end
