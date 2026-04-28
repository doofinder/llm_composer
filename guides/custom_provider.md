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

## Optional: Response Normalization Adapter

For complex response shapes, implement a `LlmComposer.ProviderResponse.*` adapter instead of
building the `LlmResponse` inline. See the existing provider response modules in
`lib/llm_composer/provider_response/` for the pattern.

## Optional: Streaming Support

To support streaming, implement a `LlmComposer.ProviderStreamChunk.*` module using the
`Struct` macro:

```elixir
defmodule MyApp.Providers.MyProvider.StreamChunk do
  use LlmComposer.ProviderStreamChunk.Struct,
    parser: MyApp.Providers.MyProvider.StreamChunk.Parser,
    provider: :my_provider
end

defmodule MyApp.Providers.MyProvider.StreamChunk.Parser do
  def parse(chunk_map, _provider, _opts) do
    # Map provider-specific chunk map to LlmComposer.StreamChunk fields
    {:ok, %LlmComposer.StreamChunk{type: :text_delta, text: chunk_map["delta"]}}
  end
end
```
