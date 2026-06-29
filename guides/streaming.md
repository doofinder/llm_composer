# Streaming

Streaming works with both built-in adapters:

- **Mint** (default) — works out of the box, no extra dependencies needed. Note that Mint opens a new connection per request and does not pool connections.
- **Finch** — also supported; use it if you need connection pooling or already have Finch in your stack.

To use Finch for streaming, add the dependency, start it in your supervision tree, and configure the adapter:

```elixir
# mix.exs
{:finch, "~> 0.18"}

# application.ex
{Finch, name: MyApp.Finch}

# config/config.exs
config :llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyApp.Finch}
```

Enable streaming by setting `stream_response: true` in your provider options. The response
`LlmResponse.t()` will have its `:stream` field populated with an `Enumerable` of
`LlmComposer.StreamChunk` structs.

## Basic Usage

```elixir
Application.put_env(:llm_composer, :google, api_key: "<your google api key>")

settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.Google, [model: "gemini-2.5-flash"]}
  ],
  system_prompt: "You are a helpful assistant.",
  stream_response: true
}

{:ok, res} = LlmComposer.run_completion(settings, [
  %LlmComposer.Message{type: :user, content: "How did the Roman Empire grow so big?"}
])

res.stream
|> LlmComposer.parse_stream_response(res.provider)
|> Enum.each(fn chunk ->
  IO.write(chunk.text || "")
end)
```

## parse_stream_response/2

`LlmComposer.parse_stream_response/2` normalizes the raw provider stream into
`%LlmComposer.StreamChunk{}` values, making chunk handling consistent across providers:

```elixir
res.stream
|> LlmComposer.parse_stream_response(res.provider)
|> Enum.each(fn chunk ->
  case chunk.type do
    :text_delta -> IO.write(chunk.text)
    :done -> IO.puts("\n[done]")
    :error -> IO.puts("\n[error] #{inspect(chunk.metadata)}")
    _ -> :ok
  end
end)
```

Key fields on each chunk:

| Field | Description |
|---|---|
| `:provider` | Source provider (`:open_ai`, `:google`, `:open_router`, etc.) |
| `:type` | Event category (see chunk types below) |
| `:text` | Incremental text when available |
| `:usage` | Normalized token counts when exposed by the provider |
| `:raw` | Original decoded payload for advanced/debug handling |

## Token Tracking in Streaming Mode

When streaming is enabled, LlmComposer does **not** populate `LlmResponse` token fields
(`:input_tokens`, `:output_tokens`, etc.) from the response. Two approaches:

1. **Calculate tokens externally** — use a library like `tiktoken` for OpenAI-compatible
   providers before sending the request.
2. **Read from stream events** — some providers (OpenRouter, OpenAI Responses) include token
   counts in their `:usage` or `:done` chunk events. Read `chunk.usage` when `chunk.type == :usage`.

## StreamChunk Fields

`LlmComposer.StreamChunk.t()` carries all information about a single streaming event:

| Field | Type | Description |
|---|---|---|
| `:provider` | `atom()` | Provider that emitted this chunk |
| `:type` | `atom()` | Event type (see below) |
| `:text` | `String.t() \| nil` | Text delta for this chunk |
| `:reasoning` | `String.t() \| nil` | Reasoning delta (reasoning models) |
| `:reasoning_details` | `list()` | Structured reasoning blocks |
| `:tool_calls` | `list()` | Partial tool call fragments |
| `:usage` | `map() \| nil` | Token counts when reported mid-stream |
| `:cost_info` | `CostInfo.t() \| nil` | Cost info when `:track_costs` is enabled |
| `:metadata` | `map()` | Provider-specific extra data |
| `:raw` | `any()` | Original decoded payload |

## Chunk Types

| Type | Description |
|---|---|
| `:text_delta` | Incremental text content |
| `:reasoning_delta` | Incremental reasoning content |
| `:tool_call_delta` | Partial tool/function call |
| `:usage` | Token usage report |
| `:done` | Stream finished successfully |
| `:error` | Stream encountered an error |
| `:unknown` | Unrecognized event (safe to skip) |

## Assembling the Full Text

```elixir
full_text =
  res.stream
  |> LlmComposer.parse_stream_response(res.provider)
  |> Stream.filter(&(&1.type == :text_delta))
  |> Enum.map_join("", & &1.text)
```

## Streaming and Retries

Streaming is **not** compatible with Tesla's retry middleware. When `stream_response: true`
is set, the retry middleware is removed automatically. See the
[Configuration guide](configuration.html) for retry options.

## Streaming with `LlmComposer.Agent`

`LlmComposer.Agent.run/3` also supports streaming. With `stream_response: true` it returns
`{:ok, stream}` where the stream carries the final answer token-by-token as `:text_delta` chunks,
interspersed with `:tool_call` chunks for each executed tool, and ends with a terminal `:done`
chunk. The terminal chunk's `:usage` and `:cost_info` hold the run totals, and
`metadata.agent_result` holds the full `LlmComposer.Agent.Result`. Intermediate tool-calling turns
run internally (streamed tool-call deltas are reassembled automatically).

Supported providers: `:open_ai`, `:open_router`, `:open_ai_responses`, `:google`, `:bedrock`,
`:ollama`. Note that `:ollama`'s native streaming format does not carry tool-call deltas — text
streaming works, but for tool-call streaming point the `:open_ai` provider at Ollama's
OpenAI-compatible endpoint instead.

```elixir
{:ok, stream} = LlmComposer.Agent.run(settings, "What's the weather in Paris?")

stream
|> Enum.reduce(nil, fn
  %LlmComposer.StreamChunk{type: :text_delta, text: t}, acc ->
    IO.write(t); acc

  %LlmComposer.StreamChunk{type: :tool_call, tool_calls: [call]}, acc ->
    IO.puts("\n[tool] #{call.name}(#{call.arguments}) → #{inspect(call.result)}"); acc

  %LlmComposer.StreamChunk{type: :done, metadata: %{agent_result: result}}, _ ->
    result

  _other, acc ->
    acc
end)
```

### Progress events for UIs

For advanced use cases (e.g. broadcasting via `Phoenix.PubSub`), tool calls and reasoning are also
exposed via `:telemetry`. Pass `telemetry_metadata:` to scope a handler to a single run:

```elixir
{:ok, stream} = LlmComposer.Agent.run(settings, prompt, telemetry_metadata: %{conversation_id: cid})

:telemetry.attach("agent-ui", [:llm_composer, :agent, :tool, :start], fn
  _event, _meas, %{conversation_id: ^cid, name: name, arguments: args}, _cfg ->
    Phoenix.PubSub.broadcast(MyApp.PubSub, "conv:#{cid}", {:tool_call, name, args})
end, nil)
```

See the [Agent guide](agent.md) for the full streaming API, all chunk types, options, and the
complete telemetry event reference.
