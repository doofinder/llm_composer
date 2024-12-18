defmodule LlmComposer.Settings do
  @moduledoc """
  Defines the settings for configuring chat interactions with a language model.

  This module provides a struct that includes model configuration, prompt settings, and options for function execution, enabling fine control over the chat flow and behavior.
  """

  @enforce_keys [:model, :model_opts]
  defstruct [
    :model,
    :model_opts,
    auto_exec_functions: false,
    functions: [],
    system_prompt: nil,
    user_prompt_prefix: "",
    api_key: nil
  ]

  @type t :: %__MODULE__{
          auto_exec_functions: boolean(),
          functions: [LlmComposer.Function.t()],
          model: module(),
          model_opts: keyword(),
          system_prompt: String.t() | nil,
          user_prompt_prefix: String.t(),
          api_key: String.t() | nil
        }
end
