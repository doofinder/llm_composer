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

  @typedoc """
  Configuration for a chat request.

  - `:api_key` — API key for the provider (not needed for all providers).
  - `:provider` — provider module (e.g. `LlmComposer.Providers.OpenAI`). Used with `:provider_opts`.
  - `:provider_opts` — keyword list of options forwarded to the single provider.
  - `:providers` — list of `{module, opts}` tuples for multi-provider routing via `ProvidersRunner`.
  - `:stream_response` — when `true`, the provider returns a streaming enumerable.
  - `:system_prompt` — system prompt string sent to the model.
  - `:track_costs` — when `true`, token usage and cost are computed and attached to the response.
  - `:user_prompt_prefix` — string prepended to every user message content.
  """
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
