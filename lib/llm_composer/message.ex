defmodule LlmComposer.Message do
  @moduledoc """
  Module that represents an arbitrary message for any LLM.
  """

  @type t :: %__MODULE__{
          type: binary() | atom(),
          content: binary() | [map()],
          metadata: map()
        }

  @enforce_keys [:type]
  defstruct [:type, :content, :metadata]

  @doc """
  Creates a new message struct with a given type and content.
  """
  @spec new(type :: binary() | atom(), content :: binary() | [map()] | nil, metadata :: map()) ::
          t()
  def new(type, content, metadata \\ %{})
      when is_binary(type) or is_atom(type) do
    %__MODULE__{type: type, content: content, metadata: metadata}
  end
end
