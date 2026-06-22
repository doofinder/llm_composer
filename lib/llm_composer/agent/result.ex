defmodule LlmComposer.Agent.Result do
  @moduledoc """
  Result of a completed `LlmComposer.Agent` run.

  Returned as `{:ok, %LlmComposer.Agent.Result{}}` by `LlmComposer.Agent.run/3` when the loop
  reaches a final, tool-free assistant response. It bundles the final response together with the
  full conversation, the executed tool calls, and accumulated cost information so callers can
  inspect, persist, or display the entire run.

  ## Fields

  - `:response` — the final `LlmComposer.LlmResponse.t()` (the tool-free assistant answer).
  - `:messages` — the full conversation, including the user message(s), assistant tool-call
    messages and `:tool_result` messages appended on each iteration. Suitable for persistence or
    for continuing the conversation.
  - `:iterations` — number of model turns performed (each call to the provider counts as one).
  - `:cost_infos` — list of `LlmComposer.CostInfo.t()`, one per model turn that reported cost
    information, in turn order (turns without cost info are omitted). Requires `track_costs: true`
    in settings. Each entry is also emitted on the per-iteration telemetry event, so callers can
    record costs incrementally rather than only at the end of the run.
  - `:function_calls` — every executed `LlmComposer.FunctionCall.t()` across all iterations, in
    execution order, each carrying its `:result`.
  """

  alias LlmComposer.CostInfo
  alias LlmComposer.FunctionCall
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @type t() :: %__MODULE__{
          response: LlmResponse.t(),
          messages: [Message.t()],
          iterations: non_neg_integer(),
          cost_infos: [CostInfo.t()],
          function_calls: [FunctionCall.t()]
        }

  @enforce_keys [:response, :messages, :iterations]
  defstruct response: nil,
            messages: [],
            iterations: 0,
            cost_infos: [],
            function_calls: []
end
