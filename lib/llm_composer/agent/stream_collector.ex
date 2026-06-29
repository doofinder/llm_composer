defmodule LlmComposer.Agent.StreamCollector do
  @moduledoc """
  Accumulates the `LlmComposer.StreamChunk`s of a single agent turn and reassembles them into a
  synthetic `LlmComposer.LlmResponse`.

  Streaming providers emit tool calls incrementally and in provider-specific shapes:

  - **OpenAI / OpenRouter** send `:tool_call_delta` chunks whose `tool_calls` are raw maps keyed by
    `"index"`, with the `function.arguments` JSON split across several chunks. They must be grouped
    by index and concatenated.
  - **OpenAI Responses** sends a `"function_call_started"` map (carries `"call_id"` and `"name"`)
    followed by one or more `"function_call_arguments_delta"` maps (carry `"call_id"` and
    `"arguments_delta"`). Fragments are grouped by `"call_id"` and concatenated in arrival order.
  - **Google** sends already-complete `LlmComposer.FunctionCall` structs (one per chunk).
  - **Bedrock** sends two event types per tool call: a start event with `"toolUseId"` and `"name"`,
    followed by one or more delta events that carry only `"inputJson"` fragments. Fragments are
    grouped by `"toolUseId"` and concatenated in arrival order.
  - **Ollama** (native provider) does not emit tool-call deltas in its streaming format; text
    streaming works. For tool-call streaming with Ollama, use the `:open_ai` provider pointed at
    Ollama's OpenAI-compatible endpoint.

  This collector hides those differences. Feed every chunk of a turn through `add/2`, then call
  `tool_turn?/1` to know whether the model requested tools, and `to_llm_response/1` to obtain a
  response shaped exactly like a non-streaming one (so the rest of `LlmComposer.Agent` can reuse the
  synchronous loop unchanged).
  """

  alias LlmComposer.CostInfo
  alias LlmComposer.FunctionCall
  alias LlmComposer.FunctionCallExtractors
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message
  alias LlmComposer.StreamChunk

  @supported_providers [:open_ai, :open_router, :open_ai_responses, :google, :bedrock, :ollama]

  @type t() :: %__MODULE__{
          provider: atom(),
          text: iodata(),
          reasoning: iodata(),
          tool_fragments: %{optional(non_neg_integer() | String.t()) => map()},
          tool_id_sequence: [String.t()],
          current_tool_id: String.t() | nil,
          function_calls: [FunctionCall.t()],
          saw_tool_call: boolean(),
          usage: StreamChunk.usage() | nil,
          cost_info: CostInfo.t() | nil
        }

  defstruct provider: nil,
            text: [],
            reasoning: [],
            tool_fragments: %{},
            tool_id_sequence: [],
            current_tool_id: nil,
            function_calls: [],
            saw_tool_call: false,
            usage: nil,
            cost_info: nil

  @doc """
  Creates a collector for the given provider.

  Raises `ArgumentError` for providers that are not yet supported by the streaming agent.
  """
  @spec new(atom()) :: t()
  def new(provider) when provider in @supported_providers do
    %__MODULE__{provider: provider}
  end

  def new(provider) do
    raise ArgumentError,
          "streaming agent does not support provider #{inspect(provider)} yet " <>
            "(supported: #{inspect(@supported_providers)})"
  end

  @doc """
  Accumulates a single `LlmComposer.StreamChunk` into the collector.
  """
  @spec add(t(), StreamChunk.t()) :: t()
  def add(%__MODULE__{} = collector, %StreamChunk{type: :text_delta, text: text})
      when is_binary(text) do
    %{collector | text: [collector.text, text]}
  end

  def add(%__MODULE__{} = collector, %StreamChunk{type: :reasoning_delta, reasoning: reasoning})
      when is_binary(reasoning) do
    %{collector | reasoning: [collector.reasoning, reasoning]}
  end

  def add(%__MODULE__{} = collector, %StreamChunk{type: :tool_call_delta, tool_calls: tool_calls})
      when is_list(tool_calls) do
    collector
    |> Map.put(:saw_tool_call, true)
    |> merge_tool_calls(tool_calls)
  end

  def add(%__MODULE__{} = collector, %StreamChunk{} = chunk) do
    collector
    |> maybe_put_usage(chunk.usage)
    |> maybe_put_cost_info(chunk.cost_info)
  end

  @doc """
  Returns `true` once any tool-call delta has been accumulated.
  """
  @spec tool_turn?(t()) :: boolean()
  def tool_turn?(%__MODULE__{saw_tool_call: saw_tool_call}), do: saw_tool_call

  @doc """
  Returns the accumulated reasoning text, or `nil` when none was streamed.
  """
  @spec reasoning(t()) :: String.t() | nil
  def reasoning(%__MODULE__{reasoning: reasoning}), do: blank_to_nil(reasoning)

  @doc """
  Finalizes the accumulated tool-call deltas into complete `LlmComposer.FunctionCall` structs.
  """
  @spec to_function_calls(t()) :: [FunctionCall.t()]
  def to_function_calls(%__MODULE__{provider: :google, function_calls: calls}), do: calls

  def to_function_calls(%__MODULE__{provider: p, tool_fragments: fragments})
      when p in [:open_ai, :open_router] do
    fragments
    |> Enum.sort_by(fn {index, _fragment} -> index end)
    |> Enum.map(fn {_index, fragment} -> fragment end)
    |> then(&FunctionCallExtractors.from_tool_calls(%{"tool_calls" => &1}))
    |> List.wrap()
  end

  def to_function_calls(%__MODULE__{
        provider: :bedrock,
        tool_fragments: fragments,
        tool_id_sequence: order
      }) do
    Enum.map(order, fn tool_id ->
      %{"toolUseId" => id, "name" => name, "inputJson" => args} = Map.fetch!(fragments, tool_id)
      %FunctionCall{id: id, name: name, arguments: args, type: "function"}
    end)
  end

  def to_function_calls(%__MODULE__{
        provider: :open_ai_responses,
        tool_fragments: fragments,
        tool_id_sequence: order
      }) do
    Enum.map(order, fn call_id ->
      %{"call_id" => id, "name" => name, "arguments" => args} = Map.fetch!(fragments, call_id)
      %FunctionCall{id: id, name: name, arguments: args, type: "function"}
    end)
  end

  def to_function_calls(%__MODULE__{}), do: []

  @doc """
  Builds a synthetic `LlmComposer.LlmResponse` equivalent to a non-streaming response for the turn.

  The returned response has an `:assistant` `main_response` carrying the accumulated text, reasoning
  and reassembled function calls, plus token usage and cost info captured from the stream.
  """
  @spec to_llm_response(t()) :: LlmResponse.t()
  def to_llm_response(%__MODULE__{} = collector) do
    usage = collector.usage || %{}
    function_calls = to_function_calls(collector)

    main_response = %Message{
      type: :assistant,
      content: blank_to_nil(collector.text),
      function_calls: function_calls,
      reasoning: blank_to_nil(collector.reasoning),
      metadata: %{}
    }

    LlmResponse.new(%{
      provider: collector.provider,
      status: :ok,
      main_response: main_response,
      input_tokens: Map.get(usage, :input_tokens),
      output_tokens: Map.get(usage, :output_tokens),
      cached_tokens: Map.get(usage, :cached_tokens),
      reasoning_tokens: Map.get(usage, :reasoning_tokens),
      cost_info: collector.cost_info
    })
  end

  @doc """
  Sums a list of per-turn `LlmComposer.CostInfo` into a single aggregate, or `nil` when empty.

  Token counts are added and `Decimal` cost fields are summed. `provider_name`, `provider_model`
  and `currency` are taken from the first entry (a run may span models).
  """
  @spec aggregate_cost_infos([CostInfo.t()]) :: CostInfo.t() | nil
  def aggregate_cost_infos([]), do: nil

  def aggregate_cost_infos([first | _] = cost_infos) do
    initial = %CostInfo{
      provider_name: first.provider_name,
      provider_model: first.provider_model,
      currency: first.currency,
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      cached_tokens: 0,
      input_cost: nil,
      output_cost: nil,
      total_cost: nil,
      metadata: %{aggregated: true, count: length(cost_infos)}
    }

    Enum.reduce(cost_infos, initial, fn cost_info, acc ->
      %CostInfo{
        acc
        | input_tokens: acc.input_tokens + (cost_info.input_tokens || 0),
          output_tokens: acc.output_tokens + (cost_info.output_tokens || 0),
          total_tokens: acc.total_tokens + (cost_info.total_tokens || 0),
          cached_tokens: acc.cached_tokens + (cost_info.cached_tokens || 0),
          input_cost: add_decimal(acc.input_cost, cost_info.input_cost),
          output_cost: add_decimal(acc.output_cost, cost_info.output_cost),
          total_cost: add_decimal(acc.total_cost, cost_info.total_cost)
      }
    end)
  end

  # Private functions

  @spec merge_tool_calls(t(), [map() | FunctionCall.t()]) :: t()
  defp merge_tool_calls(%__MODULE__{provider: :google} = collector, tool_calls) do
    new_calls = Enum.filter(tool_calls, &match?(%FunctionCall{}, &1))
    %{collector | function_calls: collector.function_calls ++ new_calls}
  end

  defp merge_tool_calls(%__MODULE__{provider: p} = collector, tool_calls)
       when p in [:open_ai, :open_router] do
    fragments =
      Enum.reduce(tool_calls, collector.tool_fragments, fn raw, acc ->
        index = Map.get(raw, "index", map_size(acc))
        Map.update(acc, index, raw, &merge_fragment(&1, raw))
      end)

    %{collector | tool_fragments: fragments}
  end

  defp merge_tool_calls(%__MODULE__{provider: :bedrock} = collector, tool_calls) do
    Enum.reduce(tool_calls, collector, fn
      %{"toolUseId" => tool_id, "name" => name} = raw, acc ->
        fragment = %{
          "toolUseId" => tool_id,
          "name" => name,
          "inputJson" => Map.get(raw, "inputJson", "")
        }

        %{
          acc
          | tool_fragments: Map.put(acc.tool_fragments, tool_id, fragment),
            tool_id_sequence: acc.tool_id_sequence ++ [tool_id],
            current_tool_id: tool_id
        }

      %{"inputJson" => input}, acc when is_binary(input) ->
        tool_id = acc.current_tool_id

        fragments =
          Map.update!(acc.tool_fragments, tool_id, fn f ->
            Map.update(f, "inputJson", input, &(&1 <> input))
          end)

        %{acc | tool_fragments: fragments}
    end)
  end

  defp merge_tool_calls(%__MODULE__{provider: :open_ai_responses} = collector, tool_calls) do
    Enum.reduce(tool_calls, collector, fn
      %{"type" => "function_call_started", "call_id" => call_id, "name" => name}, acc ->
        fragment = %{"call_id" => call_id, "name" => name, "arguments" => ""}

        %{
          acc
          | tool_fragments: Map.put(acc.tool_fragments, call_id, fragment),
            tool_id_sequence: acc.tool_id_sequence ++ [call_id],
            current_tool_id: call_id
        }

      %{
        "type" => "function_call_arguments_delta",
        "call_id" => call_id,
        "arguments_delta" => delta
      },
      acc
      when is_binary(delta) ->
        # The API delta event omits call_id; fall back to the most recently started call.
        target_id = call_id || acc.current_tool_id

        fragments =
          Map.update!(acc.tool_fragments, target_id, fn f ->
            Map.update(f, "arguments", delta, &(&1 <> delta))
          end)

        %{acc | tool_fragments: fragments}

      _other, acc ->
        acc
    end)
  end

  @spec merge_fragment(map(), map()) :: map()
  defp merge_fragment(existing, incoming) do
    Map.merge(existing, incoming, fn
      "function", existing_fun, incoming_fun -> merge_function(existing_fun, incoming_fun)
      _key, existing_val, incoming_val -> existing_val || incoming_val
    end)
  end

  @spec merge_function(map(), map()) :: map()
  defp merge_function(existing_fun, incoming_fun) do
    existing_args = Map.get(existing_fun, "arguments", "")
    incoming_args = Map.get(incoming_fun, "arguments", "")

    existing_fun
    |> Map.merge(incoming_fun, fn _key, existing_val, incoming_val ->
      existing_val || incoming_val
    end)
    |> Map.put("arguments", (existing_args || "") <> (incoming_args || ""))
  end

  @spec maybe_put_usage(t(), StreamChunk.usage() | nil) :: t()
  defp maybe_put_usage(collector, nil), do: collector
  defp maybe_put_usage(collector, usage), do: %{collector | usage: usage}

  @spec maybe_put_cost_info(t(), CostInfo.t() | nil) :: t()
  defp maybe_put_cost_info(collector, nil), do: collector
  defp maybe_put_cost_info(collector, cost_info), do: %{collector | cost_info: cost_info}

  @spec blank_to_nil(iodata()) :: String.t() | nil
  defp blank_to_nil(iodata) do
    case IO.iodata_to_binary(iodata) do
      "" -> nil
      binary -> binary
    end
  end

  @spec add_decimal(Decimal.t() | nil, Decimal.t() | nil) :: Decimal.t() | nil
  defp add_decimal(nil, nil), do: nil
  defp add_decimal(nil, value), do: value
  defp add_decimal(value, nil), do: value
  defp add_decimal(left, right), do: Decimal.add(left, right)
end
