# Agent Loop

`LlmComposer.Agent` runs an **automatic tool-calling loop** on top of
`LlmComposer.run_completion/3`. Where `simple_chat/2` and `run_completion/3` perform a single model
turn — leaving you to execute any requested tool calls and re-prompt manually (see the
[Function Calls guide](function_calls.md)) — the agent automates the whole cycle:

```
ask → model requests tool calls → execute them → feed the results back → repeat
      → until the model returns a final, tool-free answer
```

The loop works with any provider that supports function calling (**OpenAI**, **OpenRouter**,
**Google**, **Bedrock**). Both synchronous and [streaming](#streaming) modes are supported.

## Quick start

```elixir
defmodule MyTools do
  @spec calculator(map()) :: number()
  def calculator(%{"expression" => expression}) do
    {result, _binding} = Code.eval_string(expression)
    result
  end
end

calculator = %LlmComposer.Function{
  mf: {MyTools, :calculator},
  name: "calculator",
  description: "Evaluates a math expression",
  schema: %{
    "type" => "object",
    "properties" => %{"expression" => %{"type" => "string"}},
    "required" => ["expression"]
  }
}

settings = %LlmComposer.Settings{
  providers: [
    {LlmComposer.Providers.OpenAI, [model: "gpt-4.1-mini", functions: [calculator]]}
  ],
  system_prompt: "You are a helpful assistant.",
  api_key: "<your api key>",
  track_costs: true
}

{:ok, result} = LlmComposer.Agent.run(settings, "How much is (2 + 3) * 4?")

IO.puts(result.response.main_response.content)
# => "The result is 20."
IO.inspect(result.iterations)
# => 2
```

The `:functions` available to the model are read from the provider options in `settings` by
default, so you normally do not pass them again to `run/3`.

## Input

`run/3` accepts either:

- a **prompt string** — wrapped into a `:user` message (honouring the settings'
  `:user_prompt_prefix`), or
- an explicit **list of `LlmComposer.Message.t()`** — useful to continue an existing conversation.

## The result

A successful synchronous run returns `{:ok, %LlmComposer.Agent.Result{}}`:

| Field | Description |
|---|---|
| `:response` | The final `LlmComposer.LlmResponse.t()` (tool-free assistant answer). |
| `:messages` | The full conversation, including assistant tool-call messages and `:tool_result` messages. Ready to persist or continue. |
| `:iterations` | Number of model turns performed. |
| `:cost_infos` | List of `LlmComposer.CostInfo.t()`, one per turn that reported costs (requires `track_costs: true`). |
| `:function_calls` | Every executed `LlmComposer.FunctionCall.t()`, in order, each carrying its `:result`. |

## Options

| Option | Default | Description |
|---|---|---|
| `:max_iterations` | `10` | Maximum model turns before giving up. Exceeding it returns `{:error, :max_iterations_reached}`. |
| `:functions` | from settings | Tools available to the model. |
| `:tool_execution` | `:sequential` | `:sequential` runs tool calls one by one; `:parallel` runs them concurrently (`Task.async_stream/3`) while preserving result order. |
| `:tool_timeout` | `:infinity` | Per-task timeout (ms or `:infinity`) used in `:parallel` mode. |
| `:telemetry_metadata` | `%{}` | Map merged into the metadata of every agent telemetry event. An auto-generated `:run_id` is always added. Useful for scoping handlers to a single run. |

## Error handling

- **Tool errors** (unknown tool, invalid arguments, exception during execution) do **not** abort the
  loop. The error is formatted as an `"Error: ..."` string and fed back to the model as the tool
  result, giving it a chance to recover or explain the failure.
- **Model/network errors** returned by the provider abort the loop and are returned as
  `{:error, reason}`.

## Streaming

Pass `stream_response: true` in your settings and `run/3` returns `{:ok, stream}` — a lazy
`Enumerable` of `LlmComposer.StreamChunk` — instead of `{:ok, result}`.

The stream contains:

- **`:text_delta`** chunks — the final answer, token by token.
- **`:tool_call`** chunks — one per executed tool call (with the result already filled in), emitted
  right after execution and before the next LLM turn. Useful for showing progress in a UI without
  needing a telemetry handler.
- A terminal **`:done`** chunk whose `:usage` and `:cost_info` hold the run totals, and whose
  `metadata.agent_result` holds the full `LlmComposer.Agent.Result`.
- A terminal **`:error`** chunk on hard failures (e.g. `:max_iterations_reached`).

Intermediate tool-calling turns run entirely inside the loop — only the final, tool-free answer
reaches the caller as `:text_delta` chunks.

```elixir
settings = %LlmComposer.Settings{
  providers: [{LlmComposer.Providers.OpenAI, [model: "gpt-4.1-mini", functions: [calculator]]}],
  system_prompt: "You are a helpful assistant.",
  stream_response: true,
  track_costs: true
}

{:ok, stream} = LlmComposer.Agent.run(settings, "How much is (7 + 3) * 6?")

{result, cost} =
  Enum.reduce(stream, {nil, nil}, fn
    %LlmComposer.StreamChunk{type: :text_delta, text: t}, acc ->
      IO.write(t)
      acc

    %LlmComposer.StreamChunk{type: :tool_call, tool_calls: [call]}, acc ->
      IO.puts("\n[tool] #{call.name}(#{call.arguments}) → #{inspect(call.result)}")
      acc

    %LlmComposer.StreamChunk{type: :done, metadata: %{agent_result: r}, cost_info: c}, _ ->
      {r, c}

    _other, acc ->
      acc
  end)
```

Supported providers: `:open_ai`, `:open_router`, `:open_ai_responses`, `:google`, `:bedrock`,
`:ollama`. Note that `:ollama`'s native streaming format does not include tool-call deltas — text
streaming works, but for tool calls use the `:open_ai` provider pointed at Ollama's
OpenAI-compatible endpoint. Other providers yield a terminal `:error` chunk with
`{:streaming_agent_unsupported_provider, provider}`.

See the [Streaming guide](streaming.md#streaming-with-llmcomposeragent) for more details.

## Telemetry

The loop emits `:telemetry` events you can attach handlers to. Pass `telemetry_metadata:` to
`run/3` to include extra keys (plus an auto-generated `:run_id`) in every event's metadata,
making it easy to scope a handler to a single run.

| Event | Measurements | Metadata |
|---|---|---|
| `[:llm_composer, :agent, :run, :start \| :stop \| :exception]` | `:iterations` (on stop), `:duration` | `:status` (`:ok`/`:error`/`:halted`), `:max_iterations`, `:tool_count` |
| `[:llm_composer, :agent, :iteration, :stop]` | `:tool_call_count` | `:iteration`, `:cost_info`, `:final` |
| `[:llm_composer, :agent, :tool, :start \| :stop \| :exception]` | `:duration` | `:name`, `:id`, `:arguments`, `:metadata`, `:status` (`:ok`/`:error` on stop) |
| `[:llm_composer, :agent, :reasoning, :delta]` | — | `:iteration`, `:reasoning` (streaming only) |

The per-iteration event carries that turn's `:cost_info`, so you can record costs incrementally as
each completion finishes rather than only at the end of the run.

```elixir
:telemetry.attach(
  "agent-costs",
  [:llm_composer, :agent, :iteration, :stop],
  fn _event, _measurements, %{cost_info: cost_info}, _config ->
    MyApp.Usage.record(cost_info)
  end,
  nil
)
```
