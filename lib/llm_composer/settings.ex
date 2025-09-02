defmodule LlmComposer.Settings do
  @moduledoc """
  Defines the settings for configuring chat interactions with a language model.

  This module provides a struct that includes model configuration, prompt settings, and options for function execution, enabling fine control over the chat flow and behavior.
  """

  defstruct api_key: nil,
            auto_exec_functions: false,
            functions: [],
            provider: nil,
            provider_opts: nil,
            providers: [],
            stream_response: false,
            system_prompt: nil,
            track_costs: false,
            user_prompt_prefix: ""

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          auto_exec_functions: boolean(),
          functions: [LlmComposer.Function.t()],
          provider: module() | nil,
          provider_opts: keyword() | nil,
          providers: [{module(), keyword()}],
          stream_response: boolean(),
          system_prompt: String.t() | nil,
          track_costs: boolean(),
          user_prompt_prefix: String.t()
        }
end
