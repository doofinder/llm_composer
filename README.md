# LlmComposer

**LlmComposer** is an Elixir library that simplifies the interaction with large language models (LLMs) such as OpenAI's GPT, providing a streamlined way to build and execute LLM-based applications or chatbots. It currently supports multiple model providers, including OpenAI (Chat Completions and Responses API), OpenRouter, Ollama, Bedrock, and Google (Gemini), with features like manual function calls and customizable prompts to cater to different use cases.

## Table of Contents

- [Installation](#installation)
- [Tesla Configuration](#tesla-configuration)
- [Provider Compatibility](#provider-compatibility)
- [Usage](#usage)
  - [Simple Bot Definition](#simple-bot-definition)
  - [Using message history](#using-message-history)
  - [Using Ollama Backend](#using-ollama-backend)
  - [Using OpenRouter](#using-openrouter)
  - [Using OpenAI Responses API](#using-openai-responses-api)
  - [Using AWS Bedrock](#using-aws-bedrock)
  - [Using Google (Gemini)](#using-google-gemini)
    - [Basic Google Chat Example](#basic-google-chat-example)
    - [Using Vertex AI](#using-vertex-ai)
      - [Dependencies](#dependencies)
      - [Service Account Setup](#service-account-setup)
      - [Basic Vertex AI Example](#basic-vertex-ai-example)
      - [Production Setup with Supervision Tree](#production-setup-with-supervision-tree)
      - [Vertex AI Configuration Options](#vertex-ai-configuration-options)
  - [Streaming Responses](#streaming-responses)
  - [Structured Outputs](#structured-outputs)
  - [Bot with external function call](#bot-with-external-function-call)
  - [Function Calls](#function-calls)
  - [Provider Router Simple](#provider-router-simple)
  - [Cost Tracking](#cost-tracking)
    - [Requirements](#requirements)
    - [Automatic Cost Tracking](#automatic-cost-tracking)
    - [Manual Pricing](#manual-pricing)
    - [Starting Cache in a Supervision Tree](#starting-cache-in-a-supervision-tree)
    - [Dependencies Setup](#dependencies-setup)
  - [Additional Features](#additional-features)
    - [Custom Request Parameters](#custom-request-parameters)
    - [Custom Request Headers](#custom-request-headers)
- [Configuration Reference](#configuration-reference)
  - [Configuration Overview](#configuration-reference)
  - [Retry Configuration](#retry-configuration)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `llm_composer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:llm_composer, "~> 0.15.0"}
  ]
end
```

## Tesla Configuration

LlmComposer uses Tesla for HTTP requests. You can configure the Tesla adapter globally for optimal performance, especially when using streaming responses:

```elixir
# In your config/config.exs or application startup
Application.put_env(:llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyFinch})

# customizing tesla json engine, by default JSON (or Jason if JSON not available in elixir<1.18.0)
# config :llm_composer, :json_engine, Jason

# Start Finch in your application supervision tree or manually
{:ok, _finch} = Finch.start_link(name: MyFinch, pools: %{default: [protocols: [:http1]]})
```

**Recommended Tesla adapters:**
- **Finch** (recommended): Best for streaming and production use
- **Gun**: For advanced HTTP/2 support

**Note:** When using streaming responses, Finch is the recommended adapter as it provides better streaming support and performance.

## Provider Compatibility

The following table shows which features are supported by each provider:

| Feature | OpenAI | OpenRouter | Ollama | Bedrock | Google |
|---------|--------|------------|--------|---------|--------|
| Basic Chat | ✅ | ✅ | ✅ | ✅ | ✅ |
| Streaming | ✅ | ✅ | ✅ | ❌ | ✅ |
| Function Calls | ✅ | ✅ | ❌ | ❌ | ✅ |
| Structured Outputs | ✅ | ✅ | ❌ | ❌ | ✅ |
| Cost Tracking | ✅ | ✅ | ❌ | ❌ | ✅ |
| Fallback Models | ❌ | ✅ | ❌ | ❌ | ❌ |
| Provider Routing | ❌ | ✅ | ❌ | ❌ | ❌ |

### Notes:
- **OpenRouter** offers the most comprehensive feature set, including unique capabilities like fallback models and provider routing
- **Google** provides full feature support including function calls, structured outputs, and streaming with Gemini models
- **OpenAI Responses API** is available via `LlmComposer.Providers.OpenAIResponses` (see dedicated section below)
- **Bedrock** support is provided via AWS ExAws integration and requires proper AWS configuration
- **Ollama** requires an ollama server instance to be running
- **Function Calls** - LlmComposer exposes function call handling via `FunctionExecutor.execute/2` for explicit execution; supported by OpenAI, OpenRouter, and Google
- **Streaming** is **not** compatible with Tesla **retries**.

## Usage

### Simple Bot Definition

To create a basic chatbot using LlmComposer, you need to define a Settings struct and use either `run_completion` or `simple_chat`. The example below demonstrates a simple configuration with OpenAI as the model provider:

```elixir
Application.put_env(:llm_composer, :open_ai, api_key: "<your api key>")

defmodule MyChat do

  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.OpenAI, [model: "gpt-4.1-mini"]}
    ],
    system_prompt: "You are a helpful assistant."
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end
end

{:ok, res} = MyChat.simple_chat("hi")

IO.inspect(res.main_response)
```

Example of execution:

```
mix run sample.ex

16:41:07.594 [debug] input_tokens=18, output_tokens=9
LlmComposer.Message.new(
  :assistant,
  "Hello! How can I assist you today?"
)
```

This will trigger a conversation with the assistant based on the provided system prompt.

### Using message history

For more control over the interactions, basically to send the messages history and track the context, you can use the `run_completion/3` function directly.

Here’s an example that demonstrates how to use `run_completion` with a custom message flow:

```elixir
Application.put_env(:llm_composer, :open_ai, api_key: "<your api key>")

defmodule MyCustomChat do

  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.OpenAI, [model: "gpt-4.1-mini"]}
    ],
    system_prompt: "You are an assistant specialized in history.",
    functions: []
  }

  def run_custom_chat() do
    # Define a conversation history with user and assistant messages
    messages = [
      LlmComposer.Message.new(:user, "What is the Roman Empire?"),
      LlmComposer.Message.new(:assistant, "The Roman Empire was a period of ancient Roman civilization with an autocratic government."),
      LlmComposer.Message.new(:user, "When did it begin?")
    ]

    {:ok, res} = LlmComposer.run_completion(@settings, messages)

    res.main_response
  end
end

IO.inspect(MyCustomChat.run_custom_chat())
```

Example of execution:

```
mix run custom_chat.ex

16:45:10.123 [debug] input_tokens=85, output_tokens=47
LlmComposer.Message.new(
  :assistant,
  "The Roman Empire began in 27 B.C. after the end of the Roman Republic, and it continued until 476 A.D. in the West."
)
```

### Using Ollama Backend

LlmComposer also supports the Ollama backend, allowing interaction with models hosted on Ollama.

Make sure to start the Ollama server first.

```elixir
# Set the Ollama URI in the application environment if not already configured
# Application.put_env(:llm_composer, :ollama, url: "http://localhost:11434")

defmodule MyChat do

  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.Ollama, [model: "llama3.1"]}
    ],
    system_prompt: "You are a helpful assistant."
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end
end

{:ok, res} = MyChat.simple_chat("hi")

IO.inspect(res.main_response)
```

Example of execution:

```
mix run sample_ollama.ex

17:08:34.271 [debug] input_tokens=<empty>, output_tokens=<empty>
LlmComposer.Message.new(
  :assistant,
  "How can I assist you today?",
  %{
    original: %{
      "content" => "How can I assist you today?",
      "role" => "assistant"
    }
  }
)
```

**Note:** Ollama does not provide token usage information, so `input_tokens` and `output_tokens` will always be empty in debug logs and response metadata. Function calls are also not supported with Ollama.

### Using OpenRouter

LlmComposer supports integration with [OpenRouter](https://openrouter.ai/), giving you access to a variety of LLM models through a single API compatible with OpenAI's interface. It also supports OpenRouter's feature of setting fallback models.

To use OpenRouter with LlmComposer, you'll need to:

1. Sign up for an API key from [OpenRouter](https://openrouter.ai/)
2. Configure your application to use OpenRouter's endpoint

Here's a complete example:

```elixir
# Configure the OpenRouter API key and endpoint
Application.put_env(:llm_composer, :open_router, api_key: "<your openrouter api key>")

defmodule MyOpenRouterChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.OpenRouter,
       [
         model: "anthropic/claude-3-sonnet",
         models: ["openai/gpt-4.1", "fallback-model2"],
         provider_routing: %{
           order: ["openai", "azure"]
         }
       ]}
    ],
    system_prompt: "You are a SAAS consultant"
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end
end

{:ok, res} = MyOpenRouterChat.simple_chat("Why doofinder is so awesome?")

IO.inspect(res.main_response)
```

Example of execution:

```
mix run openrouter_sample.ex

17:12:45.124 [debug] input_tokens=42, output_tokens=156
LlmComposer.Message.new(
  :assistant,
  "Doofinder is an excellent site search solution for ecommerce websites. Here are some reasons why Doofinder is considered awesome:...
)
```

#### Automatic Cost Tracking with OpenRouter

OpenRouter supports automatic cost tracking without manual pricing configuration. When `track_costs: true` is enabled, LlmComposer automatically fetches real-time pricing data from OpenRouter's API and calculates costs based on actual token usage.

```elixir
# Configure the OpenRouter API key
Application.put_env(:llm_composer, :open_router, api_key: "<your openrouter api key>")

defmodule MyOpenRouterAutoCostChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.OpenRouter,
       [
         model: "anthropic/claude-3-haiku:beta",
         track_costs: true  # Enables automatic cost tracking
       ]}
    ],
    system_prompt: "You are a helpful assistant."
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end
end

{:ok, res} = MyOpenRouterAutoCostChat.simple_chat("Explain quantum computing")

# Access automatic cost information
IO.puts("Input cost: #{Decimal.to_string(res.cost_info.input_cost, :normal)}$")
IO.puts("Output cost: #{Decimal.to_string(res.cost_info.output_cost, :normal)}$")
IO.puts("Total cost: #{Decimal.to_string(res.cost_info.total_cost, :normal)}$")
```

**Features:**
- **Automatic Pricing**: Fetches up-to-date prices from OpenRouter API without manual configuration
- **Granular Tracking**: Provides breakdown of input vs. output costs
- **Caching**: Prices are cached for 24 hours to reduce API calls
- **Error Handling**: Gracefully falls back if pricing data is unavailable

**Note:** Automatic cost tracking requires the Decimal package: `{:decimal, "~> 2.3"}`

### Using OpenAI Responses API

LlmComposer supports OpenAI's Responses API through `LlmComposer.Providers.OpenAIResponses`. This lets you use the `/responses` endpoint and still receive the normalized `LlmResponse` struct.

```elixir
Application.put_env(:llm_composer, :open_ai, api_key: "<your api key>")

defmodule MyResponsesChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.OpenAIResponses,
       [
         model: "gpt-5-nano",
         reasoning: %{effort: "low"}
       ]}
    ],
    system_prompt: "You are a concise assistant."
  }

  def ask(prompt) do
    LlmComposer.simple_chat(@settings, prompt)
  end
end

{:ok, res} = MyResponsesChat.ask("Explain quantum computing in one paragraph")
IO.inspect(res.main_response)
```

You can also pass `response_schema` in provider options for structured outputs.

### Using AWS Bedrock

LlmComposer also integrates with [Bedrock](https://aws.amazon.com/es/bedrock/) via its Converse API. This allows you to use Bedrock as a provider with any of its supported models.

Currently, function execution is **not supported** with Bedrock.

To integrate with Bedrock, LlmComposer uses the [`ex_aws`](https://hexdocs.pm/ex_aws/readme.html#aws-key-configuration) to perform its requests. So, if you plan to use Bedrock, make sure that you have configured `ex_aws` as per the official documentation of the library.

Here's a complete example:

```elixir
# In your config files:
config :ex_aws,
  access_key_id: "your key",
  secret_access_key: "your secret"
---

defmodule MyBedrockChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.Bedrock, [model: "eu.amazon.nova-lite-v1:0"]}
    ],
    system_prompt: "You are an expert in Quantum Field Theory."
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end
end

{:ok, res} = MyBedrockChat.simple_chat("What is the wave function collapse? Just a few sentences")

IO.inspect(res.main_response)
```

Example of execution:

```
%LlmComposer.Message{
  type: :assistant,
  content: "Wave function collapse is a concept in quantum mechanics that describes the transition of a quantum system from a superposition of states to a single definite state upon measurement. This phenomenon is often associated with the interpretation of quantum mechanics, particularly the Copenhagen interpretation, and it remains a topic of ongoing debate and research in the field."
}
```

### Using Google (Gemini)

LlmComposer supports Google's Gemini models through the Google AI API. This provider offers comprehensive features including function calls, streaming responses, and structured outputs.

To use Google with LlmComposer, you'll need to:

1. Get an API key from [Google AI Studio](https://aistudio.google.com/)
2. Configure your application with the Google API key

#### Basic Google Chat Example

```elixir
# Configure the Google API key
Application.put_env(:llm_composer, :google, api_key: "<your google api key>")

defmodule MyGoogleChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.Google, [model: "gemini-2.5-flash"]}
    ],
    system_prompt: "You are a helpful assistant."
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end
end

{:ok, res} = MyGoogleChat.simple_chat("What is quantum computing?")

IO.inspect(res.main_response)
```

**Note:** Google provider supports all major LlmComposer features including function calls, structured outputs, and streaming. The provider uses Google's Gemini models and requires a Google AI API key.

#### Using Vertex AI

LlmComposer also supports Google's Vertex AI platform, which provides enterprise-grade AI capabilities with enhanced security and compliance features. Vertex AI requires OAuth 2.0 authentication via the Goth library.

##### Dependencies

Add Goth to your dependencies for Vertex AI authentication:

```elixir
def deps do
  [
    {:llm_composer, "~> 0.15.0"},
    {:goth, "~> 1.4"}  # Required for Vertex AI
  ]
end
```

##### Service Account Setup

1. Create a service account in Google Cloud Console
2. Grant the following IAM roles:
   - `Vertex AI User` or `Vertex AI Service Agent`
   - `Service Account Token Creator` (if using impersonation)
3. Download the JSON credentials file

##### Basic Vertex AI Example

```elixir
# Read service account credentials
google_json = File.read!(Path.expand("~/path/to/service-account.json"))
credentials = Jason.decode!(google_json)

# Optional: Configure HTTP client for Goth with retries
http_client = fn opts ->
  client =
    Tesla.client([
      {Tesla.Middleware.Retry,
       delay: 500,
       max_retries: 2,
       max_delay: 1_000,
       should_retry: fn
         {:ok, %{status: status}}, _env, _context when status in [400, 500] -> true
         {:ok, _reason}, _env, _context -> false
         {:error, _reason}, %Tesla.Env{method: :post}, _context -> false
         {:error, _reason}, %Tesla.Env{method: :put}, %{retries: 2} -> false
         {:error, _reason}, _env, _context -> true
       end}
    ])

  Tesla.request(client, opts)
end

# Start Goth process
{:ok, _pid} =
  Goth.start_link(
    source: {:service_account, credentials},
    # Optional: improves reliability
    http_client: http_client,
    name: MyApp.Goth
  )

# Configure LlmComposer to use your Goth process
Application.put_env(:llm_composer, :google, goth: MyApp.Goth)

defmodule MyVertexChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.Google,
       [
         model: "gemini-2.5-flash",
         vertex: %{
           project_id: "my-gcp-project",
           # or specific region like "us-central1"
           location_id: "global"
         }
       ]}
    ],
    system_prompt: "You are a helpful assistant."
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end
end

{:ok, res} = MyVertexChat.simple_chat("What are the benefits of Vertex AI?")

IO.inspect(res.main_response)
```

##### Production Setup with Supervision Tree

For production applications, add Goth to your supervision tree:

```elixir
# In your application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    google_json = File.read!(Application.get_env(:my_app, :google_credentials_path))
    credentials = Jason.decode!(google_json)

    children = [
      # Other children...
      {Goth, name: MyApp.Goth, source: {:service_account, credentials}},
      # ... rest of your children
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

# Configure in config.exs
config :llm_composer, :google, goth: MyApp.Goth
config :my_app, :google_credentials_path, "/path/to/service-account.json"
```

##### Vertex AI Configuration Options

The `:vertex` map accepts the following options:

- `:project_id` (required) - Your Google Cloud project ID
- `:location_id` (required) - The location/region for your Vertex AI endpoint (e.g., "us-central1", "global")
- `:api_endpoint` (optional) - Custom API endpoint (overrides default regional endpoint)

**Note:** Vertex AI provides the same feature set as Google AI API but with enterprise security, audit logging, and VPC support. All LlmComposer features including function calls, streaming, and structured outputs are fully supported.

### Streaming Responses

LlmComposer supports streaming responses for real-time output, which is particularly useful for long-form content generation. This feature works with providers that support streaming (like OpenRouter, OpenAI, and Google).

**Note:** The `stream_response: true` setting enables streaming mode. When using streaming, LlmComposer does not track input/output/cache/thinking tokens. There are two approaches to handle token counting in this mode:

1. Calculate tokens using libraries like `tiktoken` for OpenAI provider.
2. Read token data from the last stream object if the provider supplies it (currently only OpenRouter supports this).

Here's a complete example of how to use streaming with Google's Gemini:

```elixir
# Configure the Google API key
Application.put_env(:llm_composer, :google, api_key: "<your google api key>")
Application.put_env(:llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyFinch})

defmodule StreamingChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.Google, [model: "gemini-2.5-flash"]}
    ],
    system_prompt: "You are a helpful assistant.",
    stream_response: true
  }

  def run_streaming_chat() do
    messages = [
      %LlmComposer.Message{type: :user, content: "How did the Roman Empire grow so big?"}
    ]
    
    {:ok, res} = LlmComposer.run_completion(@settings, messages)

    # Process the stream and display each chunk as it arrives
    res.stream
    |> LlmComposer.parse_stream_response(res.provider)
    |> Enum.each(fn chunk ->
      # Each `chunk` is an %LlmComposer.StreamChunk{} struct with normalized text, usage, and raw data
      IO.write(chunk.text || "")
    end)
  end
end

# Start Finch for HTTP streaming support
{:ok, _finch} = Finch.start_link(name: MyFinch, pools: %{default: [protocols: [:http1]]})

StreamingChat.run_streaming_chat()
```

The streaming response allows you to display content to users as it's being generated, providing a better user experience for longer responses.

`parse_stream_response/2` returns normalized `%LlmComposer.StreamChunk{}` values across providers. Useful fields include:

- `provider`: stream source provider (`:open_ai`, `:open_router`, `:google`, `:ollama`)
- `type`: event category (`:text_delta`, `:tool_call_delta`, `:done`, `:unknown`)
- `text`: incremental text when available
- `usage`: normalized token usage (when exposed by the provider)
- `raw`: original decoded payload for advanced/debug handling

### Structured Outputs

OpenRouter/Google/OpenAI supports structured outputs by allowing you to specify a `response_schema` in the provider options. This enables the model to return responses conforming to a defined JSON schema, which is helpful for applications requiring strict formatting and validation of the output.

To use structured outputs, include the `response_schema` key inside the provider options (the second element of each provider tuple) in the settings, like this:

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

The model will then produce responses that adhere to the specified JSON schema, making it easier to parse and handle results programmatically.

**Note:** This feature is currently supported on the OpenRouter, Google, and OpenAI providers in llm_composer.

### Function Calls

LlmComposer supports **manual function call execution** using the `FunctionExecutor` module. This approach gives you full control over when and how function calls are executed, without automatic execution. This is useful when you need to:

- Log or audit function calls before execution
- Apply custom validation or filtering to function calls
- Execute multiple function calls in parallel with custom error handling
- Integrate with external systems before/after execution

Here's a concise, self-contained example demonstrating the 3-step manual function-call workflow (no external sample files required):

```elixir
# Configure provider API key
Application.put_env(:llm_composer, :open_ai, api_key: "<your api key>")

defmodule ManualFunctionCallExample do
  alias LlmComposer.FunctionExecutor
  alias LlmComposer.Function
  alias LlmComposer.Message

  # 1) Define the actual function that will run locally
  @spec calculator(map()) :: number() | {:error, String.t()}
  def calculator(%{"expression" => expr}) do
    # simple validation to avoid arbitrary evaluation
    if Regex.match?(~r/^[0-9\.\s\+\-\*\/\(\)]+$/, expr) do
      {result, _} = Code.eval_string(expr)
      result
    else
      {:error, "invalid expression"}
    end
  end

  # 2) Define the function descriptor sent to the model
  defp calculator_function do
    %Function{
      mf: {__MODULE__, :calculator},
      name: "calculator",
      description: "Evaluate arithmetic expressions",
      schema: %{
        "type" => "object",
        "properties" => %{"expression" => %{"type" => "string"}},
        "required" => ["expression"]
      }
    }
  end

  def run() do
    functions = [calculator_function()]

    settings = %LlmComposer.Settings{
      providers: [
        {LlmComposer.Providers.OpenAI, [model: "gpt-4o-mini", functions: functions]}
      ],
      system_prompt: "You are a helpful math assistant."
    }

    user_prompt = "What is 15 + 27?"

    # Step 1: send initial chat that may request function calls
    {:ok, resp} = LlmComposer.simple_chat(settings, user_prompt)

    case resp.function_calls do
      nil ->
        # Model provided a direct answer
        IO.puts("Assistant: #{resp.main_response.content}")
        {:ok, resp}

      function_calls ->
        # Step 2: execute each returned function call locally
        executed_calls =
          Enum.map(function_calls, fn call ->
            case FunctionExecutor.execute(call, functions) do
              {:ok, executed} -> executed
              {:error, _} -> call
            end
          end)

        # Build tool-result messages (helper constructs proper :tool_result messages)
        tool_messages = LlmComposer.FunctionCallHelpers.build_tool_result_messages(executed_calls)

        # Build assistant 'with tools' message (provider-aware helper)
        user_message = %Message{type: :user, content: user_prompt}

        assistant_with_tools =
          LlmComposer.FunctionCallHelpers.build_assistant_with_tools(
            LlmComposer.Providers.OpenAI,
            resp,
            user_message,
            [model: "gpt-4o-mini", functions: functions]
          )

        # Step 3: send user + assistant(with tool calls) + tool results back to LLM
        messages = [user_message, assistant_with_tools] ++ tool_messages

        {:ok, final} = LlmComposer.run_completion(settings, messages)
        IO.puts("Assistant: #{final.main_response.content}")
        {:ok, final}
    end
  end
end

# Run the example
ManualFunctionCallExample.run()
```

**What this shows**
- How to define a safe local function and a corresponding `LlmComposer.Function` descriptor.
- How to call `LlmComposer.simple_chat/2` to obtain potential function calls from the model.
- How to execute returned `FunctionCall` structs with `FunctionExecutor.execute/2`.
- How to build `:tool_result` messages with `LlmComposer.FunctionCallHelpers.build_tool_result_messages/1` and construct the assistant message using `build_assistant_with_tools/4`.
- How to submit the results back to the model with `LlmComposer.run_completion/2` to receive the final assistant answer.

#### FunctionExecutor API

The `FunctionExecutor.execute/2` function:

```elixir
FunctionExecutor.execute(function_call, function_definitions)
```

**Parameters:**
- `function_call`: The `FunctionCall` struct returned by the LLM
- `function_definitions`: List of `Function` structs that define callable functions

**Returns:**
- `{:ok, executed_call}`: FunctionCall with `:result` populated
- `{:error, :function_not_found}`: Function name not in definitions
- `{:error, {:invalid_arguments, reason}}`: Failed to parse JSON arguments
- `{:error, {:execution_failed, reason}}`: Exception during execution

**Supported Providers:** OpenAI, OpenRouter, and Google (Gemini)

### Provider Router Simple

LlmComposer introduces a new provider routing mechanism to support multi-provider configurations with failover and fallback logic. The default router implementation is `LlmComposer.ProviderRouter.Simple`, which provides an exponential backoff blocking strategy on provider failures.

#### Configuration

Configure the provider router in your application environment:

```elixir
# all these options are the default, you can specify just the ones you want to override
config :llm_composer, :provider_router,
  min_backoff_ms: 1_000,                    # 1 second minimum backoff (default)
  max_backoff_ms: :timer.minutes(5),        # 5 minutes maximum backoff (default)
  cache_mod: LlmComposer.Cache.Ets,         # Cache module to use (default)
  cache_opts: [                             # Cache options (default shown below)
    name: LlmComposer.ProviderRouter.Simple,
    table_name: :llm_composer_provider_blocks
  ],
  name: LlmComposer.ProviderRouter.Simple   # Router instance name (default)
```

#### Backoff Strategy

The router uses exponential backoff with the following formula:
```
backoff_ms = min(max_backoff_ms, min_backoff_ms * 2^(failure_count - 1))
```

Examples with default settings:
- 1st failure: 1 second
- 2nd failure: 2 seconds
- 3rd failure: 4 seconds
- 4th failure: 8 seconds
- 5th failure: 16 seconds
- ...continuing until max_backoff_ms (5 minutes)

#### Behavior

- **Success**: Provider is unblocked and failure count is reset
- **Failure**: Provider is blocked for exponential backoff period
- **Blocking**: Blocked providers are skipped during provider selection
- **Recovery**: Providers automatically become available after backoff period expires
- **Persistence**: Blocking state is stored in ETS for fast access during runtime. To achieve persistence across restarts, you can implement a custom cache backend that stores data on disk or in a database.

#### Usage

To use multi-provider support with routing and fallback, define your settings with the `:providers` list instead of the deprecated `:provider` and `:provider_opts` keys:

```elixir
@settings %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenAI, [model: "gpt-4.1-mini"]},
    {LlmComposer.Providers.Google, [model: "gemini-2.5-flash"]}
  ],
  system_prompt: "You are a helpful assistant."
}
```

The `LlmComposer.ProvidersRunner` will handle provider selection, routing, and fallback automatically using the configured router.

#### Complete Example

Here's a comprehensive example showing how to set up and use the provider router with multiple providers:

```elixir
Application.put_env(:llm_composer, :open_ai, api_key: "<your openai api key>")
Application.put_env(:llm_composer, :open_router, api_key: "<your openrouter api key>")
# Configure Ollama with wrong URL to demonstrate failover
Application.put_env(:llm_composer, :ollama, url: "http://localhost:99999")

defmodule MultiProviderChat do
  @settings %LlmComposer.Settings{
    providers: [
      # Primary provider - will fail due to wrong URL, demonstrating failover
      {LlmComposer.Providers.Ollama, [model: "llama3.1"]},
      # Fallback provider - will be used when Ollama fails
      {LlmComposer.Providers.OpenAI, [model: "gpt-4.1-mini"]},
      # Additional fallback provider
      {LlmComposer.Providers.OpenRouter, [model: "google/gemini-2.5-flash"]}
    ],
    system_prompt: "You are a helpful math assistant."
  }

  def chat_with_fallback(message) do
    messages = [
      %LlmComposer.Message{type: :user, content: message}
    ]

    case LlmComposer.run_completion(@settings, messages) do
      {:ok, response} ->
        IO.puts("Response received from provider")
        response.main_response

      {:error, reason} ->
        IO.puts("All providers failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def demo_fallback_behavior() do
    # Make multiple requests to demonstrate fallback behavior
    # If the first provider fails, it will be blocked and subsequent requests
    # will automatically use the next available provider

    Enum.each(1..5, fn i ->
      IO.puts("\n--- Request #{i} ---")
      result = chat_with_fallback("What is #{i} + #{i}?")
      IO.inspect(result, label: "Result")

      Process.sleep(1000)
    end)
  end
end

# Start the provider router (required for multi-provider support)
# In production, add this to your application's supervision tree
{:ok, _router_pid} = LlmComposer.ProviderRouter.Simple.start_link([])

# Optional: Configure custom router settings
# Application.put_env(:llm_composer, :provider_router, [
#   name: MyCustomRouter,
#   min_backoff_ms: 2_000,
#   max_backoff_ms: :timer.minutes(10)
# ])

MultiProviderChat.demo_fallback_behavior()
```

#### Fallback Logic

The router will skip providers that are currently blocked due to recent failures and try the next available provider in the list. Providers are blocked with an exponential backoff strategy, increasing the block duration on repeated failures.

This mechanism ensures high availability and resilience by automatically failing over to healthy providers without manual intervention.

### Cost Tracking

LlmComposer provides built-in cost tracking functionality for **OpenAI**, **OpenRouter**, and **Google** providers to monitor token usage and associated costs. This feature helps you keep track of API expenses and optimize your usage by providing detailed cost breakdowns per request.

**OpenAI**, **OpenRouter**, and **Google** support automatic cost tracking that fetches real-time pricing data from their respective APIs (models.dev API for OpenAI/Google, OpenRouter API for OpenRouter), eliminating the need for manual pricing configuration.

#### Requirements

To use cost tracking, you need:

1. **Decimal package**: Add `{:decimal, "~> 2.0"}` to your dependencies in `mix.exs`
2. **Cache backend**: A cache implementation for storing cost data (LlmComposer provides an ETS-based cache by default, or you can implement a custom one using `LlmComposer.Cache.Behaviour`)

#### Automatic Cost Tracking

**OpenAI** and **Google** support automatic cost tracking via the models.dev dataset. When you enable `track_costs: true` and do not supply explicit prices, LlmComposer will fetch pricing from models.dev and cache it (ETS). Start the cache before using automatic pricing.

```elixir
# OpenAI automatic pricing example
Application.put_env(:llm_composer, :open_ai, api_key: "<your openai api key>")

# Start the cache backend (required for automatic pricing fetching)
{:ok, _} = LlmComposer.Cache.Ets.start_link()

defmodule MyOpenAICostTrackingChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.OpenAI,
       [
         model: "gpt-4o-mini",
         track_costs: true
         # these are optional, if not provided, this data is fetched from models.dev api and cached with ets
         # input_price_per_million: "0.150",
         # output_price_per_million: "0.600"
       ]}
    ],
    system_prompt: "You are a helpful assistant."
  }

  def run_chat_with_costs() do
    messages = [
      %LlmComposer.Message{type: :user, content: "Explain quantum computing briefly"}
    ]

    {:ok, res} = LlmComposer.run_completion(@settings, messages)

    # Access cost information from the response
    IO.puts("Provider: #{res.cost_info.provider_name}")
    IO.puts("Model: #{res.cost_info.provider_model}")
    IO.puts("Total tokens: #{res.cost_info.total_tokens}")
    IO.puts("Total cost: #{Decimal.to_string(res.cost_info.total_cost, :normal)}$")

    res
  end
end

MyOpenAICostTrackingChat.run_chat_with_costs()
```

**Google** uses the same setup (replace provider with `LlmComposer.Providers.Google` and model with e.g. `"gemini-2.5-flash"`).


#### Automatic Cost Tracking (OpenRouter)

OpenRouter also supports automatic pricing via its API. Start the cache and enable `track_costs: true`; prices will be fetched and cached if not provided.

```elixir
Application.put_env(:llm_composer, :open_router, api_key: "<your openrouter api key>")

# Start the cache backend (required for automatic pricing fetching)
{:ok, _} = LlmComposer.Cache.Ets.start_link()

defmodule MyOpenRouterCostTrackingChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.OpenRouter,
       [
         model: "anthropic/claude-3-haiku:beta",
         track_costs: true,
         # these are optional, if not provided, this data is fetched from openrouter api and cached with ets
         # input_price_per_million: "0.250",
         # output_price_per_million: "1.250"
       ]}
    ],
    system_prompt: "You are a helpful assistant."
  }

  def run_chat_with_costs() do
    messages = [
      %LlmComposer.Message{type: :user, content: "Explain quantum computing briefly"}
    ]

    {:ok, res} = LlmComposer.run_completion(@settings, messages)

    # Access cost information from the response
    IO.puts("Provider: #{res.cost_info.provider_name}")
    IO.puts("Model: #{res.cost_info.provider_model}")
    IO.puts("Total tokens: #{res.cost_info.total_tokens}")
    IO.puts("Total cost: #{Decimal.to_string(res.cost_info.total_cost, :normal)}$")

    res
  end
end

MyOpenRouterCostTrackingChat.run_chat_with_costs()
```

#### Manual Pricing (Explicit Prices — no cache required)

If you prefer to provide explicit prices for input/output tokens, you can do so and no ETS cache is required. This is useful when you already know your pricing or want to override automatic fetching.

```elixir
Application.put_env(:llm_composer, :google, api_key: "<your google api key>")

defmodule MyManualCostTrackingChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.Google,
       [
         model: "gemini-2.5-flash",
         track_costs: true,
         input_price_per_million: "0.075",
         output_price_per_million: "0.300"
       ]}
    ],
    system_prompt: "You are a helpful assistant."
  }

  def run_chat_with_costs() do
    messages = [
      %LlmComposer.Message{type: :user, content: "How much is 1 + 1?"}
    ]

    {:ok, res} = LlmComposer.run_completion(@settings, messages)

    # Access cost information from the response
    IO.puts("Input tokens: #{res.input_tokens}")
    IO.puts("Output tokens: #{res.output_tokens}")
    IO.puts("Input cost: #{Decimal.to_string(res.cost_info.input_cost, :normal)}$")
    IO.puts("Output cost: #{Decimal.to_string(res.cost_info.output_cost, :normal)}$")
    IO.puts("Total cost: #{Decimal.to_string(res.cost_info.total_cost, :normal)}$")

    res
  end
end

MyManualCostTrackingChat.run_chat_with_costs()
```


#### Starting Cache in a Supervision Tree

For production applications, add the ETS cache to your supervision tree to ensure it's available for automatic pricing fetching:

```elixir
# In your application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Other children...
      LlmComposer.Cache.Ets,  # Add this for automatic pricing caching
      # ... rest of your children
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

You can also start it manually in development or testing:

```elixir
# Start the cache manually
{:ok, _} = LlmComposer.Cache.Ets.start_link()
```

#### Dependencies Setup

Add the decimal dependency to your `mix.exs`:

```elixir
def deps do
  [
    {:llm_composer, "~> 0.15.0"},
    {:decimal, "~> 2.3"}  # Required for cost tracking
  ]
end
```

**Note:** Automatic pricing requires starting the ETS cache (see Starting Cache section). Manual pricing does not require the cache. If automatic pricing sources (models.dev or OpenRouter API) are unavailable, token counts are still tracked, but costs will be nil. All cost information is available in the `CostInfo` struct within responses.

### Additional Features

#### Custom Request Parameters

LlmComposer supports passing custom request parameters to LLM provider APIs through the `request_params` option. This allows you to customize provider-specific parameters that are merged with the base request body.

**Supported Providers:** All providers (OpenAI, OpenRouter, Ollama, Bedrock, Google)

**Example with OpenAI:**

```elixir
Application.put_env(:llm_composer, :open_ai, api_key: "<your api key>")

defmodule MyCustomChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.OpenAI, [
        model: "gpt-5-mini",
        request_params: %{
          reasoning_effort: "low"
        }
      ]}
    ],
    system_prompt: "You are a helpful assistant."
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end
end

{:ok, res} = MyCustomChat.simple_chat("Explain quantum computing")
IO.inspect(res.main_response)
```

**Example with OpenRouter:**

```elixir
Application.put_env(:llm_composer, :open_router, api_key: "<your openrouter api key>")

defmodule MyOpenRouterCustomChat do
  @settings %LlmComposer.Settings{
    providers: [
      {LlmComposer.Providers.OpenRouter, [
        model: "anthropic/claude-3-haiku",
        request_params: %{
          temperature: 0.3,
          max_tokens: 500
        }
      ]}
    ],
    system_prompt: "You are a helpful assistant."
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end
end

{:ok, res} = MyOpenRouterCustomChat.simple_chat("What is machine learning?")
IO.inspect(res.main_response)
```

**Note:** Custom parameters are merged with the base request body. Provider-specific parameters (like `temperature`, `max_tokens`, `reasoning_effort`) can be passed through `request_params` to fine-tune model behavior.

* System Prompts: Customize the assistant's behavior by modifying the system prompt (e.g., creating different personalities or roles for your bot).

#### Custom Request Headers

You can pass custom headers to OpenRouter requests using the `headers` option. This is useful for passing headers like `HTTP-Referer` and `X-Title` which are recommended by OpenRouter for rankings.

**Supported Providers:** OpenRouter

**Example with OpenRouter:**

```elixir
@settings %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenRouter,
     [
       model: "anthropic/claude-3-haiku",
       headers: [
         {"HTTP-Referer", "https://my-app.com"},
         {"X-Title", "My App"}
       ]
     ]}
  ]
}
```

---

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/llm_composer>.

## Configuration Reference

### Configuration Overview

LlmComposer provides several configuration options that can be set globally in your `config/config.exs` or per-request in provider options:

| Configuration | Description | See Documentation |
|--------------|-------------|------------------|
| `:tesla_adapter` | HTTP client adapter for requests (default: Mint) | [Tesla Configuration](#tesla-configuration) |
| `:json_engine` | JSON encoder/decoder library (defaults to JSON, falls back to Jason) | [JSON Engine Configuration](#json-engine-configuration) |
| `:timeout` | Request timeout in milliseconds | - |
| `:retry_opts` / `:skip_retries` | Retry options and disable flag for requests | [Retry Configuration](#retry-configuration) |
| `:provider_router` | Provider routing and failover configuration | [Provider Router Simple](#provider-router-simple) |
| `:cache_ttl` | Cache time-to-live for pricing data in seconds | [Cost Tracking](#cost-tracking) |
| Provider configs | Provider-specific settings (`:open_ai`, `:google`, `:open_router`, `:ollama`, etc.) | See provider-specific sections below |

### Retry Configuration

LlmComposer supports HTTP retries via `Tesla.Middleware.Retry`.

**Defaults (when retries are enabled):**
- Retries on: HTTP `429`, `500`, `503`, and connection `{:error, :closed}`
- Delay: `1_000` ms
- Max delay: `10_000` ms
- Request timeout: `50_000` ms

**Important:** Streaming disables retries automatically (`stream_response: true`).

#### Global configuration (recommended)

Set defaults in `config/config.exs`:

```elixir
# Disable retries globally
config :llm_composer, :skip_retries, true

# Or customize retries globally
config :llm_composer, :retry_opts,
  max_retries: 5,
  delay: 1_000,
  max_delay: 10_000
```

You can also provide a custom `should_retry`:

```elixir
config :llm_composer, :retry_opts,
  should_retry: fn
    {:ok, %{status: status}} when status in [429, 500, 502, 503, 504] -> true
    {:error, :closed} -> true
    _ -> false
  end
```

#### Per-Request Configuration

Override retry behavior per provider entry:

* Disable retries for a single request:

  * `skip_retries: true`
* Customize retries:

  * `retry_opts: [...]`

```elixir
@settings %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenAI,
     [
       model: "gpt-4.1-mini",
       retry_opts: [max_retries: 5, delay: 2_000, max_delay: 30_000]
     ]}
  ]
}
```

#### Precedence rules

* Per-request `retry_opts` override global `retry_opts`.

Example per-request `should_retry`:

```elixir
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

#### Streaming and retries

Retries are disabled when either is true:

* Global or per-request `skip_retries: true`
* `stream_response: true` (streaming mode)

> Streaming responses are not compatible with retries; when streaming is enabled, the retry middleware is removed automatically.

#### Reference

`retry_opts` maps directly to `Tesla.Middleware.Retry` options (e.g. `:delay`, `:max_delay`, `:max_retries`, `:jitter`, `:backoff_fun`, `:should_retry`).

See Tesla docs:
[https://hexdocs.pm/tesla/1.16.0/Tesla.Middleware.Retry.html](https://hexdocs.pm/tesla/1.16.0/Tesla.Middleware.Retry.html)
