defmodule LlmComposer.Function do
  @moduledoc """
  A struct representing a function.
  """

  @type t() :: %__MODULE__{
          mf: {module(), atom()},
          name: String.t(),
          description: String.t(),
          schema: map()
        }

  defstruct mf: nil,
            name: nil,
            description: nil,
            schema: %{}
end
