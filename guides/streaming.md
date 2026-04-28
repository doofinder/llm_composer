# Streaming

> Streaming requires [Finch](https://hex.pm/packages/finch) as the HTTP client. The default
> adapter (`Tesla.Adapter.Mint`) does not work with Tesla's SSE middleware, so Finch is needed
> for streaming. Follow these steps to set it up:
>
> **1. Add the dependency** (`mix.exs`):
> ```elixir
> {:finch, "~> 0.18"}
> ```
>
> **2. Start Finch** in your application supervisor (`application.ex`):
> ```elixir
> {Finch, name: MyApp.Finch}
> ```
>
> **3. Configure LlmComposer** to use the Finch adapter (`config/config.exs`):
> ```elixir
> config :llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyApp.Finch}
> ```

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
