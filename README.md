# LlmComposer

**LlmComposer** is an Elixir library that simplifies interaction with large language models (LLMs). It provides a unified interface to OpenAI (Chat Completions and Responses API), OpenRouter, Ollama, AWS Bedrock, and Google (Gemini), with support for streaming, function calls, structured outputs, cost tracking, and multi-provider failover routing.

## Table of Contents

- [Installation](#installation)
- [Tesla Configuration](#tesla-configuration)
- [Provider Compatibility](#provider-compatibility)
- [Usage](#usage)
  - [Simple Chat](#simple-chat)
  - [Using Message History](#using-message-history)
  - [Providers](#providers)
- [Full Documentation](#full-documentation)

## Installation

Add `llm_composer` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:llm_composer, "~> 0.19"}
  ]
end
```

## Tesla Configuration

LlmComposer uses Tesla for HTTP. The default adapter is `Tesla.Adapter.Mint`. For streaming
responses, configure Finch instead:

```elixir
# config/config.exs
config :llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyApp.Finch}

# application.ex supervision tree
{Finch, name: MyApp.Finch}
```

You can also customize the JSON engine (defaults to `JSON`, falls back to `Jason`):

```elixir
config :llm_composer, :json_engine, Jason
```

## Provider Compatibility

| Feature | OpenAI | OpenRouter | Ollama | Bedrock | Google |
|---|---|---|---|---|---|
| Basic Chat | ✅ | ✅ | ✅ | ✅ | ✅ |
| Streaming | ✅ | ✅ | ✅ | ✅ | ✅ |
| Function Calls | ✅ | ✅ | ⚠️¹ | ✅ | ✅ |
| Structured Outputs | ✅ | ✅ | ⚠️¹ | ✅ | ✅ |
| Cost Tracking | ✅ | ✅ | ❌ | ✅ | ✅ |
| Fallback Models | ❌ | ✅ | ❌ | ❌ | ❌ |
| Provider Routing | ❌ | ✅ | ❌ | ❌ | ❌ |

¹ Via Ollama's OpenAI-compatible endpoint — see the [Providers guide](https://hexdocs.pm/llm_composer/providers.html).

## Usage

### Simple Chat

```elixir
Application.put_env(:llm_composer, :open_ai, api_key: "<your api key>")

settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenAI, [model: "gpt-4.1-mini"]}
  ],
  system_prompt: "You are a helpful assistant."
}

{:ok, res} = LlmComposer.simple_chat(settings, "hi")
IO.inspect(res.main_response)
```

### Using Message History

For multi-turn conversations, use `run_completion/2` with an explicit message list:

```elixir
messages = [
  LlmComposer.Message.new(:user, "What is the Roman Empire?"),
  LlmComposer.Message.new(:assistant, "The Roman Empire was a period of ancient Roman civilization."),
  LlmComposer.Message.new(:user, "When did it begin?")
]

{:ok, res} = LlmComposer.run_completion(settings, messages)
IO.inspect(res.main_response)
```

### Providers

All five providers share the same interface. Quick references:

| Provider | Setup |
|---|---|
| OpenAI | `Application.put_env(:llm_composer, :open_ai, api_key: "...")` |
| OpenRouter | `Application.put_env(:llm_composer, :open_router, api_key: "...")` |
| Ollama | No API key — start Ollama server locally |
| AWS Bedrock | Configure via ExAws |
| Google | `Application.put_env(:llm_composer, :google, api_key: "...")` or Goth/Vertex |

See the [Providers guide](https://hexdocs.pm/llm_composer/providers.html) for full examples,
Vertex AI setup, OpenAI-compatible servers, and provider-specific options.

## Full Documentation

Complete reference documentation is available on [HexDocs](https://hexdocs.pm/llm_composer):

- [Providers](https://hexdocs.pm/llm_composer/providers.html) — per-provider setup, Vertex AI, OpenAI-compatible servers, structured outputs, custom request params
- [Streaming](https://hexdocs.pm/llm_composer/streaming.html) — Finch setup, StreamChunk fields, token tracking
- [Function Calls](https://hexdocs.pm/llm_composer/function_calls.html) — 3-step manual function call workflow, FunctionExecutor API
- [Provider Router](https://hexdocs.pm/llm_composer/provider_router.html) — multi-provider failover with exponential backoff
- [Cost Tracking](https://hexdocs.pm/llm_composer/cost_tracking.html) — automatic and manual pricing, ETS cache setup
- [Custom Providers](https://hexdocs.pm/llm_composer/custom_provider.html) — implementing the Provider behaviour
- [Configuration](https://hexdocs.pm/llm_composer/configuration.html) — all global options, retry configuration
