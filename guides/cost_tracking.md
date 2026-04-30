# Cost Tracking

LlmComposer can automatically compute token usage and API cost for each request.
Supported providers: **OpenAI**, **OpenRouter**, **Google**, and **Bedrock**.

## Requirements

- **Decimal package**: `{:decimal, "~> 2.3"}` in your `mix.exs` deps.
- **ETS cache**: Required when using automatic pricing (not needed for manual pricing).

```elixir
# mix.exs
{:llm_composer, "~> 0.19"},
{:decimal, "~> 2.3"}
```

## Setup: Starting the Cache

For automatic pricing (fetched from OpenRouter API or models.dev), the ETS cache must be
running before requests are made.

**In a supervision tree (production):**

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      LlmComposer.Cache.Ets
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

**Manually (development / testing):**

```elixir
{:ok, _} = LlmComposer.Cache.Ets.start_link()
```

## Enabling Cost Tracking

Set `track_costs: true` in provider options:

```elixir
settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenAI,
     [
       model: "gpt-4o-mini",
       track_costs: true
     ]}
  ],
  system_prompt: "You are a helpful assistant."
}

{:ok, response} = LlmComposer.simple_chat(settings, "Explain quantum computing briefly")

IO.puts("Provider: #{response.cost_info.provider_name}")
IO.puts("Model: #{response.cost_info.provider_model}")
IO.puts("Total tokens: #{response.cost_info.total_tokens}")
IO.puts("Total cost: #{Decimal.to_string(response.cost_info.total_cost, :normal)}$")
```

## CostInfo Fields

`LlmComposer.CostInfo.t()` is attached to `LlmResponse.t()` as `:cost_info`:

| Field | Type | Description |
|---|---|---|
| `:provider_name` | `atom()` | Provider identifier |
| `:provider_model` | `String.t()` | Model identifier |
| `:input_tokens` | `non_neg_integer()` | Tokens in the request |
| `:output_tokens` | `non_neg_integer()` | Tokens in the response |
| `:total_tokens` | `non_neg_integer()` | Total tokens consumed |
| `:cached_tokens` | `non_neg_integer()` | Tokens served from cache |
| `:input_cost` | `Decimal.t()` | Cost of input tokens |
| `:output_cost` | `Decimal.t()` | Cost of output tokens |
| `:total_cost` | `Decimal.t()` | Total cost |
| `:input_price_per_million` | `Decimal.t()` | Price per 1M input tokens |
| `:output_price_per_million` | `Decimal.t()` | Price per 1M output tokens |
| `:cache_read_price_per_million` | `Decimal.t() \| nil` | Price per 1M cache-read tokens |
| `:currency` | `String.t()` | Currency code (default `"USD"`) |
| `:metadata` | `map()` | Extra provider-specific data |

## Pricing Resolution

Pricing is resolved in priority order:

1. **Explicit opts** — pass `:input_price_per_million` and `:output_price_per_million` directly
2. **OpenRouter API** — fetched automatically for the OpenRouter provider
3. **models.dev API** — fetched automatically for OpenAI, Google, and Bedrock
4. **nil** — token counts are still tracked, but cost fields will be `nil`

Prices fetched from external APIs are cached in ETS for 24 hours (configurable via
`:cache_ttl`).

## Manual Pricing

Provide prices explicitly — no ETS cache required:

```elixir
provider_opts: [
  model: "gemini-2.5-flash",
  track_costs: true,
  input_price_per_million: "0.075",
  output_price_per_million: "0.300"
]
```

## Cached Token Billing

When a provider reports cached tokens, they are deducted from input tokens and billed at
`:cache_read_price_per_million` if set. This reflects the discounted rate most providers
apply for cache hits.

## Per-Provider Notes

- **OpenRouter** — pricing fetched from OpenRouter's API, includes real-time model prices.
- **OpenAI / Google / Bedrock** — pricing fetched from [models.dev](https://models.dev) API.
- **Ollama** — cost tracking is not supported (no token usage reported).
