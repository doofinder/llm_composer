# Provider Router

LlmComposer supports multi-provider configurations with automatic failover via
`LlmComposer.ProviderRouter.Simple`. When one provider fails, the router blocks it with
exponential backoff and tries the next one in the list.

## Setup

Add the router to your supervision tree (or start it manually in development):

```elixir
# application.ex
children = [
  LlmComposer.ProviderRouter.Simple
]
```

```elixir
# development / scripts
{:ok, _} = LlmComposer.ProviderRouter.Simple.start_link([])
```

## Configuration

All options have defaults; override only what you need:

```elixir
config :llm_composer, :provider_router,
  min_backoff_ms: 1_000,                   # 1 second minimum backoff
  max_backoff_ms: :timer.minutes(5),       # 5 minutes maximum backoff
  cache_mod: LlmComposer.Cache.Ets,        # cache backend
  cache_opts: [
    name: LlmComposer.ProviderRouter.Simple,
    table_name: :llm_composer_provider_blocks
  ],
  name: LlmComposer.ProviderRouter.Simple  # router process name
```

## Usage

Define your settings with the `:providers` list. `LlmComposer.ProvidersRunner` handles
provider selection and fallback automatically.

```elixir
settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenAI, [model: "gpt-4.1-mini"]},
    {LlmComposer.Providers.Google, [model: "gemini-2.5-flash"]}
  ],
  system_prompt: "You are a helpful assistant."
}

{:ok, response} = LlmComposer.run_completion(settings, messages)
```

## Backoff Strategy

Uses exponential backoff:

```
backoff_ms = min(max_backoff_ms, min_backoff_ms × 2^(failure_count - 1))
```

With default settings:

| Failure # | Blocked for |
|---|---|
| 1st | 1 second |
| 2nd | 2 seconds |
| 3rd | 4 seconds |
| 4th | 8 seconds |
| 5th | 16 seconds |
| ... | up to 5 minutes |

## Behavior

| Event | Effect |
|---|---|
| Success | Provider unblocked, failure count reset |
| Failure | Provider blocked for backoff period |
| Blocked provider selected | Skipped, next provider tried |
| Backoff expires | Provider becomes available again |

Blocking state is stored in ETS for fast access. To persist blocks across restarts,
implement a custom cache backend using `LlmComposer.Cache.Behaviour`.

## Complete Example

```elixir
Application.put_env(:llm_composer, :open_ai, api_key: "<your openai api key>")
Application.put_env(:llm_composer, :open_router, api_key: "<your openrouter api key>")
# Wrong URL to demonstrate failover
Application.put_env(:llm_composer, :ollama, url: "http://localhost:99999")

{:ok, _} = LlmComposer.ProviderRouter.Simple.start_link([])

settings = %LlmComposer.Settings{
  providers: [
    # Primary — will fail due to wrong URL
    {LlmComposer.Providers.Ollama, [model: "llama3.1"]},
    # First fallback
    {LlmComposer.Providers.OpenAI, [model: "gpt-4.1-mini"]},
    # Second fallback
    {LlmComposer.Providers.OpenRouter, [model: "google/gemini-2.5-flash"]}
  ],
  system_prompt: "You are a helpful assistant."
}

# First call: Ollama fails → blocked → OpenAI responds
# Subsequent calls: Ollama skipped (blocked) → OpenAI responds directly
{:ok, response} = LlmComposer.run_completion(settings, [
  %LlmComposer.Message{type: :user, content: "What is 2 + 2?"}
])
IO.inspect(response.main_response)
```
