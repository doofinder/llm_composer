# Configuration Reference

All configuration is set via `Application.put_env/3` or `config/config.exs`.

## Global Options

| Key | Default | Description |
|---|---|---|
| `:tesla_adapter` | `Tesla.Adapter.Mint` | HTTP client adapter. Both Mint (default) and Finch support streaming. |
| `:json_engine` | `JSON` (or `Jason` on Elixir < 1.18) | JSON encoder/decoder module. |
| `:timeout` | `50_000` ms | Default request timeout. |
| `:skip_retries` | `false` | Disable retries globally. |
| `:retry_opts` | see below | Default `Tesla.Middleware.Retry` options. |
| `:provider_router` | see [Provider Router guide](provider_router.html) | Multi-provider failover config. |
| `:cache_ttl` | `86_400` (24 hours) | Cache TTL in seconds for pricing data. |

### Provider-Specific Keys

| Key | Provider |
|---|---|
| `:open_ai` | `LlmComposer.Providers.OpenAI` and `OpenAIResponses` |
| `:open_router` | `LlmComposer.Providers.OpenRouter` |
| `:ollama` | `LlmComposer.Providers.Ollama` |
| `:google` | `LlmComposer.Providers.Google` |
| `:ex_aws` | `LlmComposer.Providers.Bedrock` (via ExAws) |

Each provider key accepts at minimum `:api_key` and `:url` overrides:

```elixir
config :llm_composer, :open_ai,
  api_key: System.get_env("OPENAI_API_KEY"),
  url: "https://api.openai.com/v1"
```

---

## Retry Configuration

LlmComposer retries failed requests via `Tesla.Middleware.Retry`.

**Defaults:**

- Retries on: HTTP `429`, `500`, `503`, and `{:error, :closed}`
- Delay: `1_000` ms
- Max delay: `10_000` ms
- Request timeout: `50_000` ms

> Streaming (`stream_response: true`) disables retries automatically — the retry middleware
> is removed when streaming mode is active.

### Global Configuration

```elixir
# Disable retries globally
config :llm_composer, :skip_retries, true

# Customize retry behavior
config :llm_composer, :retry_opts,
  max_retries: 5,
  delay: 1_000,
  max_delay: 10_000

# Custom retry predicate
config :llm_composer, :retry_opts,
  should_retry: fn
    {:ok, %{status: status}} when status in [429, 500, 502, 503, 504] -> true
    {:error, :closed} -> true
    _ -> false
  end
```

### Per-Request Configuration

Override retry behavior for a single provider entry:

```elixir
{LlmComposer.Providers.OpenAI,
 [
   model: "gpt-4.1-mini",
   retry_opts: [max_retries: 5, delay: 2_000, max_delay: 30_000]
 ]}

# Disable retries for one request
{LlmComposer.Providers.OpenAI,
 [
   model: "gpt-4.1-mini",
   skip_retries: true
 ]}

# Per-request should_retry
{LlmComposer.Providers.OpenAI,
 [
   model: "gpt-4.1-mini",
   retry_opts: [
     should_retry: fn
       {:ok, %{status: 429}} -> true
       _ -> false
     end
   ]
 ]}
```

**Precedence:** per-request `retry_opts` override global `retry_opts`.

### Available retry_opts Keys

Maps directly to `Tesla.Middleware.Retry` options. See the
[Tesla docs](https://hexdocs.pm/tesla/Tesla.Middleware.Retry.html) for the full list:
`:delay`, `:max_delay`, `:max_retries`, `:jitter`, `:backoff_fun`, `:should_retry`.

---

## Tesla Adapter

The default adapter is `Tesla.Adapter.Mint`, which supports streaming out of the box.
Note that Mint opens a new connection per request and does not pool connections — use Finch
if connection pooling matters for your workload:

```elixir
# config/config.exs
config :llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyApp.Finch}
```

See the [Streaming guide](streaming.html) for the full Finch setup.

---

## JSON Engine

By default LlmComposer uses the built-in `JSON` module (Elixir ≥ 1.18) or falls back to
`Jason`. To force a specific engine:

```elixir
config :llm_composer, :json_engine, Jason
```
