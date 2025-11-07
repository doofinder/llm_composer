defmodule LlmComposer.Settings do
  @moduledoc """
  Defines the settings for configuring chat interactions with a language model.

  This module provides a struct that includes model configuration and prompt settings, enabling fine control over the chat flow and behavior.
  """

  defstruct api_key: nil,
            provider: nil,
            provider_opts: nil,
            providers: nil,
            stream_response: false,
            system_prompt: nil,
            track_costs: false,
            user_prompt_prefix: ""

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          provider: module() | nil,
          provider_opts: keyword() | nil,
          providers: [{module(), keyword()}] | nil,
          stream_response: boolean(),
          system_prompt: String.t() | nil,
          track_costs: boolean(),
          user_prompt_prefix: String.t()
        }
end
