defmodule LlmComposer.FunctionCall do
  @moduledoc """
  Helper struct for function call actions.
  """
  @type t() :: %__MODULE__{
          arguments: binary(),
          id: binary(),
          metadata: map(),
          name: binary,
          result: term,
          type: binary() | nil
        }

  defstruct [
    :arguments,
    :id,
    :metadata,
    :name,
    :result,
    :type
  ]
end
