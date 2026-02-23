defmodule LlmComposer.Provider do
  @moduledoc """
  Behaviour for provider modules used by `LlmComposer`.

  A provider is responsible for:

  - receiving normalized `LlmComposer.Message` inputs,
  - calling an upstream API,
  - returning a normalized `LlmComposer.LlmResponse`.

  ## Required callbacks

  - `name/0`: returns the provider atom (for example, `:open_ai`, `:google`).
  - `run/3`: executes one completion request.

  `run/3` receives:

  - `messages`: user/assistant/tool messages,
  - `system_message`: system prompt message (or `nil`),
  - `opts`: provider options (model, credentials, request params, stream flag, etc.).

  It must return:

  - `{:ok, %LlmComposer.LlmResponse{}}` on success,
  - `{:error, reason}` on failure.

  ## Minimal implementation shape

  ```elixir
  defmodule LlmComposer.Providers.MyProvider do
    @behaviour LlmComposer.Provider

    @impl LlmComposer.Provider
    def name, do: :my_provider

    @impl LlmComposer.Provider
    def run(messages, system_message, opts) do
      # 1) validate required opts (for example, :model / auth)
      # 2) build provider request from messages + system_message
      # 3) call API and map result into {:ok, %{response: body}} | {:error, reason}
      # 4) normalize through your ProviderResponse adapter
    end
  end
  ```

  For consistency with built-in providers, implement a `LlmComposer.ProviderResponse.*`
  adapter so provider-specific payloads are parsed into `LlmComposer.LlmResponse`.
  If streaming is supported, also add a `LlmComposer.ProviderStreamChunk.*` adapter.
  """

  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @callback run([Message.t()], Message.t() | nil, keyword()) ::
              {:ok, LlmResponse.t()} | {:error, term()}

  @callback name() :: atom
end
