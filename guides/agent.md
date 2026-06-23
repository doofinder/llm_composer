# Agent Loop

`LlmComposer.Agent` runs an **automatic tool-calling loop** on top of
`LlmComposer.run_completion/3`. Where `simple_chat/2` and `run_completion/3` perform a single model
turn — leaving you to execute any requested tool calls and re-prompt manually (see the
[Function Calls guide](function_calls.md)) — the agent automates the whole cycle:

```
ask → model requests tool calls → execute them → feed the results back → repeat
      → until the model returns a final, tool-free answer
```

The loop is **synchronous** (streaming is not supported in this version) and pure orchestration
over existing building blocks, so it works with any provider that supports function calling
(**OpenAI**, **OpenRouter**, **Google**).

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

A successful run returns `{:ok, %LlmComposer.Agent.Result{}}`:

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

## Error handling

- **Tool errors** (unknown tool, invalid arguments, exception during execution) do **not** abort the
  loop. The error is formatted as an `"Error: ..."` string and fed back to the model as the tool
  result, giving it a chance to recover or explain the failure.
- **Model/network errors** returned by the provider abort the loop and are returned as
  `{:error, reason}`.
- **Streaming** settings (`stream_response: true`) return `{:error, :streaming_not_supported}`.

## Telemetry

The loop emits `:telemetry` events you can attach handlers to:

| Event | Measurements | Metadata |
|---|---|---|
| `[:llm_composer, :agent, :run, :start \| :stop \| :exception]` | `:iterations` (on stop), `:duration` | `:status` (`:ok`/`:error`), `:reason`, `:max_iterations`, `:tool_count` |
| `[:llm_composer, :agent, :iteration, :stop]` | `:tool_call_count` | `:iteration`, `:cost_info`, `:final` |
| `[:llm_composer, :agent, :tool, :start \| :stop \| :exception]` | `:duration` | `:name`, `:status` (`:ok`/`:error`) |

The per-iteration event carries that turn's `:cost_info`, so you can record costs incrementally as
each completion finishes rather than only at the end of the run.

```elixir
:telemetry.attach(
  "agent-costs",
  [:llm_composer, :agent, :iteration, :stop],
  fn _event, _measurements, %{cost_info: cost_info}, _config ->
    # persist or report cost_info for this completion
    MyApp.Usage.record(cost_info)
  end,
  nil
)
```
