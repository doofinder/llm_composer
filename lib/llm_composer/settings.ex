defmodule LlmComposer.Settings do
  @moduledoc """
  Settings for a Chat module.
  """

  @enforce_keys [:model, :model_opts]
  defstruct [
    :model,
    :model_opts,
    auto_exec_functions: false,
    functions: [],
    system_prompt: "",
    user_prompt_prefix: ""
  ]

  @type t :: %__MODULE__{
          auto_exec_functions: boolean(),
          functions: [LlmComposer.Function.t()],
          model: module(),
          model_opts: keyword(),
          system_prompt: String.t(),
          user_prompt_prefix: String.t()
        }
end
