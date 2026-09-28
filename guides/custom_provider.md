# Custom Providers

Any module that implements the `LlmComposer.Provider` behaviour can be used as a provider.

## Required Callbacks

```elixir
@callback name() :: atom()
@callback run([Message.t()], Message.t() | nil, keyword()) ::
            {:ok, LlmResponse.t()} | {:error, term()}
```

- `name/0` — returns an atom identifying your provider (e.g. `:my_provider`).
- `run/3` — executes a completion request and returns a normalized `LlmResponse`.

## Minimal Implementation

```elixir
defmodule MyApp.Providers.MyProvider do
  @behaviour LlmComposer.Provider

  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @impl LlmComposer.Provider
  def name, do: :my_provider

  @impl LlmComposer.Provider
  def run(messages, system_message, opts) do
    model = Keyword.fetch!(opts, :model)
    api_key = Keyword.fetch!(opts, :api_key)

    body = build_request(messages, system_message, model)

    case call_api(body, api_key) do
      {:ok, raw} ->
        response =
          LlmResponse.new(%{
            status: :ok,
            main_response: Message.new(:assistant, raw["text"]),
            provider: name(),
            provider_model: model,
            raw: raw
          })

        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

## Registration

Pass your module via `:provider` (single) or `:providers` (multi-provider routing):

```elixir
# Single provider
%LlmComposer.Settings{
  provider: MyApp.Providers.MyProvider,
  provider_opts: [model: "my-model", api_key: "..."]
}

# Multi-provider routing
%LlmComposer.Settings{
  providers: [
    {MyApp.Providers.MyProvider, [model: "my-model", api_key: "..."]}
  ]
}
```

## Streaming

`LlmComposer.parse_stream_response/3` only supports the built-in providers. A custom provider that
streams must parse its own stream.
