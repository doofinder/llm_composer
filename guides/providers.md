# Providers

LlmComposer ships with five built-in providers. Each implements the `LlmComposer.Provider`
behaviour and can be used interchangeably.

## Provider Overview

| Provider | Module | Auth |
|---|---|---|
| OpenAI | `LlmComposer.Providers.OpenAI` | `:api_key` |
| OpenRouter | `LlmComposer.Providers.OpenRouter` | `:api_key` |
| Ollama | `LlmComposer.Providers.Ollama` | none (local) |
| AWS Bedrock | `LlmComposer.Providers.Bedrock` | ExAws config |
| Google | `LlmComposer.Providers.Google` | `:api_key` or Goth/Vertex |

## Feature Compatibility

| Feature | OpenAI | OpenRouter | Ollama | Bedrock | Google |
|---|---|---|---|---|---|
| Basic Chat | ✅ | ✅ | ✅ | ✅ | ✅ |
| Streaming | ✅ | ✅ | ✅ | ✅ | ✅ |
| Function Calls | ✅ | ✅ | ⚠️¹ | ✅ | ✅ |
| Structured Outputs | ✅ | ✅ | ⚠️¹ | ✅ | ✅ |
| Cost Tracking | ✅ | ✅ | ❌ | ✅ | ✅ |
| Fallback Models | ❌ | ✅ | ❌ | ❌ | ❌ |
| Provider Routing | ❌ | ✅ | ❌ | ❌ | ❌ |

¹ Ollama via the native provider does not support function calls or structured outputs.
Use `LlmComposer.Providers.OpenAI` pointed at your Ollama instance's OpenAI-compatible
endpoint (`/v1/chat/completions`) to access these features on supported models.

## Common Options

All providers accept these options:

| Option | Type | Description |
|---|---|---|
| `:model` | `String.t()` | Model identifier (required) |
| `:stream_response` | `boolean()` | Enable streaming (default `false`) |
| `:request_params` | `map()` | Extra params merged into the request body |
| `:functions` | `[LlmComposer.Function.t()]` | Tool/function definitions |
| `:track_costs` | `boolean()` | Attach cost info to the response |

---

## OpenAI

```elixir
Application.put_env(:llm_composer, :open_ai, api_key: "<your api key>")

settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenAI, [model: "gpt-4o"]}
  ],
  system_prompt: "You are a helpful assistant."
}
```

### OpenAI Responses API

`LlmComposer.Providers.OpenAIResponses` targets the `/responses` endpoint and supports
reasoning models, structured outputs via `response_schema`, and streaming:

```elixir
settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenAIResponses,
     [
       model: "gpt-5-nano",
       reasoning: %{effort: "low"}
     ]}
  ],
  system_prompt: "You are a concise assistant."
}

{:ok, res} = LlmComposer.simple_chat(settings, "Explain quantum computing in one paragraph")
```

Streaming with OpenAI Responses API:

```elixir
settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenAIResponses, [model: "gpt-4o-mini"]}
  ],
  system_prompt: "You are a helpful assistant.",
  stream_response: true
}

{:ok, res} = LlmComposer.simple_chat(settings, "Write one sentence about stars")

res.stream
|> LlmComposer.parse_stream_response(res.provider)
|> Enum.each(fn chunk -> IO.write(chunk.text || "") end)
```

### OpenAI-Compatible Servers

vLLM, LocalAI, LM Studio, and Ollama's OpenAI-compatible endpoint can all be used by
overriding `:url`:

```elixir
Application.put_env(:llm_composer, :open_ai, url: "http://localhost:8000/v1", api_key: "token")

# or per-request:
provider_opts: [
  model: "mistral-7b",
  api_key: "ignored",
  url: "http://localhost:8000/v1"
]
```

For Ollama specifically:

```elixir
Application.put_env(:llm_composer, :open_ai, url: "http://localhost:11434/v1", api_key: "ollama")

{LlmComposer.Providers.OpenAI, [model: "llama3.1"]}
# or
{LlmComposer.Providers.OpenAIResponses, [model: "llama3.1"]}
```

---

## OpenRouter

OpenRouter gives access to many models through a single OpenAI-compatible API, with unique
features like fallback models and provider routing.

```elixir
Application.put_env(:llm_composer, :open_router, api_key: "<your openrouter api key>")

settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenRouter,
     [
       model: "anthropic/claude-3-sonnet",
       models: ["openai/gpt-4.1", "fallback-model2"],
       provider_routing: %{order: ["openai", "azure"]}
     ]}
  ],
  system_prompt: "You are a helpful assistant."
}
```

### Custom Headers

OpenRouter recommends sending `HTTP-Referer` and `X-Title` headers for rankings:

```elixir
provider_opts: [
  model: "anthropic/claude-3-haiku",
  headers: [
    {"HTTP-Referer", "https://my-app.com"},
    {"X-Title", "My App"}
  ]
]
```

---

## Ollama

No API key required. Start the Ollama server, then:

```elixir
# Application.put_env(:llm_composer, :ollama, url: "http://localhost:11434")

settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.Ollama, [model: "llama3.1"]}
  ],
  system_prompt: "You are a helpful assistant."
}

{:ok, res} = LlmComposer.simple_chat(settings, "hi")
IO.inspect(res.main_response)
```

> **Note:** Ollama does not report token usage. `input_tokens` and `output_tokens` will be
> empty. Function calls and structured outputs are not available through the native Ollama
> provider — use the OpenAI-compatible endpoint approach instead (see OpenAI section above).

---

## AWS Bedrock

Requires the optional `{:ex_aws, "~> 2.6"}` dependency. Credentials are read from ExAws
config. See the [ExAws documentation](https://hexdocs.pm/ex_aws/readme.html#aws-key-configuration)
for all supported credential sources.

```elixir
# config/config.exs
config :ex_aws,
  access_key_id: "your key",
  secret_access_key: "your secret"
```

```elixir
settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.Bedrock, [model: "eu.amazon.nova-lite-v1:0"]}
  ],
  system_prompt: "You are a helpful assistant."
}

{:ok, res} = LlmComposer.simple_chat(settings, "What is quantum computing?")
IO.inspect(res.main_response)
```

### Per-Service Credentials

If you need different AWS credentials for Bedrock (e.g. a dedicated IAM user), scope them
under the `"bedrock-runtime"` service key — they take precedence over the global config:

```elixir
config :ex_aws,
  access_key_id: "GLOBAL_KEY",
  secret_access_key: "GLOBAL_SECRET"

config :ex_aws,
  "bedrock-runtime": [
    access_key_id: "BEDROCK_KEY",
    secret_access_key: "BEDROCK_SECRET",
    region: "eu-west-1"
  ]
```

---

## Google

### Google AI Studio (API Key)

```elixir
Application.put_env(:llm_composer, :google, api_key: "<your google api key>")

settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.Google, [model: "gemini-2.5-flash"]}
  ],
  system_prompt: "You are a helpful assistant."
}

{:ok, res} = LlmComposer.simple_chat(settings, "What is quantum computing?")
IO.inspect(res.main_response)
```

### Vertex AI

Vertex AI requires OAuth 2.0 authentication via the [Goth](https://hexdocs.pm/goth) library.

**Dependencies:**

```elixir
{:goth, "~> 1.4"}
```

**Service Account Setup:**

1. Create a service account in Google Cloud Console.
2. Grant it the `Vertex AI User` or `Vertex AI Service Agent` IAM role.
3. Download the JSON credentials file.

**Basic Example:**

```elixir
google_json = File.read!(Path.expand("~/path/to/service-account.json"))
credentials = Jason.decode!(google_json)

{:ok, _pid} =
  Goth.start_link(
    source: {:service_account, credentials},
    name: MyApp.Goth
  )

Application.put_env(:llm_composer, :google, goth: MyApp.Goth)

settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.Google,
     [
       model: "gemini-2.5-flash",
       vertex: %{
         project_id: "my-gcp-project",
         location_id: "us-central1"
       }
     ]}
  ],
  system_prompt: "You are a helpful assistant."
}
```

**Production Setup (Supervision Tree):**

```elixir
# application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    google_json = File.read!(Application.get_env(:my_app, :google_credentials_path))
    credentials = Jason.decode!(google_json)

    children = [
      {Goth, name: MyApp.Goth, source: {:service_account, credentials}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end

# config/config.exs
config :llm_composer, :google, goth: MyApp.Goth
config :my_app, :google_credentials_path, "/path/to/service-account.json"
```

**Vertex AI Options:**

| Option | Required | Description |
|---|---|---|
| `:project_id` | yes | Google Cloud project ID |
| `:location_id` | yes | Region (e.g. `"us-central1"`, `"global"`) |
| `:api_endpoint` | no | Custom endpoint (overrides default regional endpoint) |

---

## Structured Outputs

Pass `response_schema` in provider options to get responses conforming to a JSON schema.
Supported by OpenAI, OpenRouter, Google, and Bedrock.

```elixir
settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenRouter,
     [
       model: "google/gemini-2.5-flash",
       response_schema: %{
         "type" => "object",
         "properties" => %{
           "answer" => %{"type" => "string"},
           "confidence" => %{"type" => "number"}
         },
         "required" => ["answer"]
       }
     ]}
  ]
}
```

---

## Custom Request Parameters

Use `request_params` to merge extra parameters into the provider request body. Supported by
all providers.

```elixir
# OpenAI — pass reasoning_effort
provider_opts: [
  model: "gpt-5-mini",
  request_params: %{reasoning_effort: "low"}
]

# OpenRouter — pass temperature and max_tokens
provider_opts: [
  model: "anthropic/claude-3-haiku",
  request_params: %{temperature: 0.3, max_tokens: 500}
]
```
