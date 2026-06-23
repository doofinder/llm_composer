defmodule LlmComposer.Agent do
  @moduledoc """
  Runs an agentic tool-calling loop on top of `LlmComposer.run_completion/3`.

  Where `LlmComposer.simple_chat/2` and `LlmComposer.run_completion/3` perform a single model
  turn, `LlmComposer.Agent.run/3` automates the full cycle:

      ask → model requests tool calls → execute them → feed the results back → repeat
            → until the model returns a final, tool-free answer.

  The loop is pure orchestration over existing building blocks
  (`LlmComposer.FunctionExecutor`, `LlmComposer.FunctionCallHelpers`) and does not change any
  provider behaviour.

  ## Streaming

  When `settings.stream_response` is `true`, `run/3` returns `{:ok, stream}` where `stream` is a
  lazy `Enumerable` of `LlmComposer.StreamChunk`. The stream carries **only the final, tool-free
  answer** (token-by-token `:text_delta` chunks) followed by a terminal `:done` chunk whose `:usage`
  and `:cost_info` hold the run totals and whose `metadata.agent_result` holds the full
  `LlmComposer.Agent.Result`. A hard failure (e.g. `:max_iterations_reached`) is delivered as a
  terminal `:error` chunk instead.

  Intermediate progress — tool calls, per-iteration data and reasoning — is **not** placed on the
  answer stream. It is exposed via `:telemetry` (see below) so a UI can subscribe without having to
  filter the answer.

      {:ok, stream} = LlmComposer.Agent.run(settings, "Weather in Paris?")

      stream
      |> Enum.reduce(nil, fn
        %LlmComposer.StreamChunk{type: :text_delta, text: t}, acc -> IO.write(t); acc
        %LlmComposer.StreamChunk{type: :done, metadata: %{agent_result: r}}, _ -> r
        _other, acc -> acc
      end)

  Only the `:open_ai` and `:google` providers support the streaming agent today; others yield a
  terminal `:error` chunk with `{:streaming_agent_unsupported_provider, provider}`.

  ## Example

      defmodule MyTools do
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
        providers: [{LlmComposer.Providers.OpenAI, [model: "gpt-4.1-mini", functions: [calculator]]}],
        system_prompt: "You are a helpful assistant.",
        api_key: "sk-...",
        track_costs: true
      }

      {:ok, result} = LlmComposer.Agent.run(settings, "How much is (2 + 3) * 4?")

      result.response.main_response.content
      # => "The result is 20."
      result.iterations
      # => 2

  ## Options

  - `:max_iterations` — maximum number of model turns before giving up. Defaults to `10`. When
    exceeded while the model still wants to call tools, `run/3` returns
    `{:error, :max_iterations_reached}`.
  - `:functions` — list of `LlmComposer.Function.t()` available to the model. Defaults to the
    `:functions` configured in the settings' provider options, so you usually do not need to set
    this explicitly.
  - `:tool_execution` — `:sequential` (default) runs tool calls one by one; `:parallel` runs them
    concurrently with `Task.async_stream/3` while preserving result order.
  - `:tool_timeout` — per-task timeout (ms or `:infinity`) used in `:parallel` mode. Defaults to
    `:infinity`.

  ## Tool errors

  When a tool call fails (`:function_not_found`, invalid arguments, or an exception during
  execution) the loop does **not** abort. Instead it feeds an `"Error: ..."` string back to the
  model as the tool result, giving the model a chance to recover or explain the failure. A model
  or network error returned by the provider, by contrast, aborts the loop and is returned as
  `{:error, reason}`.

  ## Telemetry

  The loop emits the following `:telemetry` events (in both synchronous and streaming modes):

  - `[:llm_composer, :agent, :run, :start | :stop | :exception]` — the whole run. The `:stop`
    event includes an `:iterations` measurement and a `:status` (`:ok`/`:error`/`:halted`) metadata
    key.
  - `[:llm_composer, :agent, :iteration, :stop]` — one per model turn. Measurement
    `:tool_call_count`; metadata `:iteration`, `:cost_info`, `:final`.
  - `[:llm_composer, :agent, :tool, :start | :stop | :exception]` — one per tool execution.
    Metadata `:name`, `:arguments`, `:metadata`, `:id` and (on stop) `:status` (`:ok`/`:error`).
  - `[:llm_composer, :agent, :reasoning, :delta]` — streaming only: one per intermediate reasoning
    fragment. Metadata `:iteration` and `:reasoning`.

  Pass `telemetry_metadata: map()` to `run/3` and the map is merged into the metadata of every event
  above, alongside an auto-generated `:run_id`. This lets a handler scope itself to a single run and,
  for example, broadcast to `Phoenix.PubSub` or `send/2` a pid:

      {:ok, _} = LlmComposer.Agent.run(settings, prompt, telemetry_metadata: %{conversation_id: cid})

      :telemetry.attach("agent-ui", [:llm_composer, :agent, :tool, :start], fn
        _event, _meas, %{conversation_id: ^cid, name: name, arguments: args}, _cfg ->
          Phoenix.PubSub.broadcast(MyApp.PubSub, "conv:\#{cid}", {:tool_call, name, args})
      end, nil)
  """

  alias LlmComposer.Agent.Result
  alias LlmComposer.Agent.StreamCollector
  alias LlmComposer.CostInfo
  alias LlmComposer.Function
  alias LlmComposer.FunctionCall
  alias LlmComposer.FunctionCallHelpers
  alias LlmComposer.FunctionExecutor
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message
  alias LlmComposer.Settings
  alias LlmComposer.StreamChunk

  require Logger

  @default_max_iterations 10

  @type input() :: String.t() | [Message.t()]

  @type run_opts() :: [
          max_iterations: pos_integer(),
          functions: [Function.t()],
          tool_execution: :sequential | :parallel,
          tool_timeout: timeout(),
          telemetry_metadata: map()
        ]

  @typep config() :: %{
           settings: Settings.t(),
           functions: [Function.t()],
           max_iterations: pos_integer(),
           tool_execution: :sequential | :parallel,
           tool_timeout: timeout(),
           telemetry_ctx: map()
         }

  @typep acc() :: %{cost_infos: [CostInfo.t()], function_calls: [FunctionCall.t()]}

  @doc """
  Runs the agentic tool-calling loop until the model returns a final, tool-free response.

  Accepts either a user prompt string (wrapped into a `:user` message, honouring the settings'
  `:user_prompt_prefix`) or an explicit list of `LlmComposer.Message.t()`.

  When `settings.stream_response` is `false`, returns `{:ok, %LlmComposer.Agent.Result{}}` on success
  or `{:error, reason}` (where `reason` may be `:max_iterations_reached` or any error returned by the
  underlying provider). When `settings.stream_response` is `true`, returns `{:ok, stream}` — see the
  "Streaming" section of the module documentation.

  See the module documentation for the available options.
  """
  @spec run(Settings.t(), input(), run_opts()) ::
          {:ok, Result.t()} | {:ok, Enumerable.t()} | {:error, term()}
  def run(settings, input, opts \\ [])

  def run(%Settings{} = settings, input, opts) do
    config = build_config(settings, opts)
    messages = normalize_input(settings, input)

    if settings.stream_response do
      {:ok, build_agent_stream(config, messages)}
    else
      run_sync(config, messages)
    end
  end

  # --- Configuration ---

  @spec build_config(Settings.t(), run_opts()) :: config()
  defp build_config(settings, opts) do
    functions = Keyword.get(opts, :functions) || functions_from_settings(settings)

    telemetry_ctx =
      opts
      |> Keyword.get(:telemetry_metadata, %{})
      |> Map.put(:run_id, System.unique_integer([:positive]))

    %{
      settings: settings,
      functions: functions,
      max_iterations: Keyword.get(opts, :max_iterations, @default_max_iterations),
      tool_execution: Keyword.get(opts, :tool_execution, :sequential),
      tool_timeout: Keyword.get(opts, :tool_timeout, :infinity),
      telemetry_ctx: telemetry_ctx
    }
  end

  # --- Synchronous loop ---

  @spec run_sync(config(), [Message.t()]) :: {:ok, Result.t()} | {:error, term()}
  defp run_sync(config, messages) do
    start_metadata = run_start_metadata(config)

    :telemetry.span([:llm_composer, :agent, :run], start_metadata, fn ->
      result = loop(config, messages, 0, new_acc())
      {result, run_measurements(result), run_stop_metadata(start_metadata, result)}
    end)
  end

  @spec run_start_metadata(config()) :: map()
  defp run_start_metadata(config) do
    Map.merge(config.telemetry_ctx, %{
      max_iterations: config.max_iterations,
      tool_count: length(config.functions)
    })
  end

  # --- Loop ---

  @spec loop(config(), [Message.t()], non_neg_integer(), acc()) ::
          {:ok, Result.t()} | {:error, term()}
  defp loop(%{max_iterations: max}, _messages, iteration, _acc) when iteration >= max do
    {:error, :max_iterations_reached}
  end

  defp loop(config, messages, iteration, acc) do
    case LlmComposer.run_completion(config.settings, messages) do
      {:ok, %LlmResponse{stream: nil} = response} ->
        handle_response(config, messages, iteration, acc, response)

      {:ok, %LlmResponse{}} ->
        {:error, :streaming_not_supported}

      {:error, _reason} = error ->
        error
    end
  end

  @spec handle_response(config(), [Message.t()], non_neg_integer(), acc(), LlmResponse.t()) ::
          {:ok, Result.t()} | {:error, term()}
  defp handle_response(config, messages, iteration, acc, response) do
    next_iteration = iteration + 1
    cost_infos = acc.cost_infos ++ List.wrap(response.cost_info)

    case LlmResponse.function_calls(response) do
      calls when calls in [nil, []] ->
        emit_iteration(config.telemetry_ctx, next_iteration, response.cost_info, 0, true)
        finalize(response, messages, next_iteration, %{acc | cost_infos: cost_infos})

      calls ->
        executed = execute_tool_calls(config, calls)

        emit_iteration(
          config.telemetry_ctx,
          next_iteration,
          response.cost_info,
          length(calls),
          false
        )

        loop(
          config,
          apply_tool_turn(config, messages, response, executed),
          next_iteration,
          %{acc | cost_infos: cost_infos, function_calls: acc.function_calls ++ executed}
        )
    end
  end

  @spec apply_tool_turn(config(), [Message.t()], LlmResponse.t(), [FunctionCall.t()]) ::
          [Message.t()]
  defp apply_tool_turn(config, messages, response, executed) do
    provider_mod = resolve_provider_module(config.settings, response.provider)
    provider_opts = provider_opts_for(config.settings, provider_mod)

    assistant_msg =
      FunctionCallHelpers.build_assistant_with_tools(
        provider_mod,
        response,
        last_user_message(messages),
        provider_opts
      )

    tool_msgs = FunctionCallHelpers.build_tool_result_messages(executed)

    messages ++ [assistant_msg | tool_msgs]
  end

  @spec finalize(LlmResponse.t(), [Message.t()], non_neg_integer(), acc()) :: {:ok, Result.t()}
  defp finalize(response, messages, iterations, acc) do
    {:ok,
     %Result{
       response: response,
       messages: messages ++ [response.main_response],
       iterations: iterations,
       cost_infos: acc.cost_infos,
       function_calls: acc.function_calls
     }}
  end

  # --- Streaming loop ---

  @spec build_agent_stream(config(), [Message.t()]) :: Enumerable.t()
  defp build_agent_stream(config, messages) do
    Stream.resource(
      fn -> start_stream(config, messages) end,
      &step/1,
      &finish_stream/1
    )
  end

  @spec start_stream(config(), [Message.t()]) :: map()
  defp start_stream(config, messages) do
    :telemetry.execute([:llm_composer, :agent, :run, :start], %{}, run_start_metadata(config))

    %{
      config: config,
      phase: :start_turn,
      messages: messages,
      iteration: 0,
      acc: new_acc(),
      usage: %{},
      cont: nil,
      collector: nil,
      status: :running
    }
  end

  @spec step(map()) :: {[StreamChunk.t()], map()} | {:halt, map()}
  defp step(%{phase: :done} = state), do: {:halt, state}
  defp step(%{phase: :start_turn} = state), do: start_turn(state)
  defp step(%{phase: :drive} = state), do: drive_turn(state)

  @spec start_turn(map()) :: {[StreamChunk.t()], map()}
  defp start_turn(%{config: config, iteration: iteration} = state) do
    if iteration >= config.max_iterations do
      terminate_error(state, :max_iterations_reached)
    else
      begin_turn(state)
    end
  end

  @spec begin_turn(map()) :: {[StreamChunk.t()], map()}
  defp begin_turn(%{config: config, messages: messages} = state) do
    case LlmComposer.run_completion(config.settings, messages) do
      {:ok, %LlmResponse{stream: nil} = response} ->
        # provider ignored stream_response and returned a complete response: handle it directly
        handle_complete_response(state, response)

      {:ok, %LlmResponse{stream: stream, provider: provider}} ->
        setup_drive(state, provider, stream)

      {:error, reason} ->
        terminate_error(state, reason)
    end
  end

  @spec setup_drive(map(), atom(), Enumerable.t()) :: {[StreamChunk.t()], map()}
  defp setup_drive(%{config: config} = state, provider, stream) do
    collector = StreamCollector.new(provider)

    parsed =
      LlmComposer.parse_stream_response(stream, provider, provider_pricing_opts(config, provider))

    {[], %{state | phase: :drive, collector: collector, cont: init_puller(parsed)}}
  rescue
    ArgumentError -> terminate_error(state, {:streaming_agent_unsupported_provider, provider})
  end

  @spec drive_turn(map()) :: {[StreamChunk.t()], map()}
  defp drive_turn(%{cont: cont, collector: collector} = state) do
    case pull(cont) do
      {:chunk, chunk, next_cont} ->
        state = %{state | collector: StreamCollector.add(collector, chunk), cont: next_cont}
        forward_chunk(state, chunk)

      :done ->
        handle_complete_response(state, StreamCollector.to_llm_response(collector))
    end
  end

  @spec forward_chunk(map(), StreamChunk.t()) :: {[StreamChunk.t()], map()}
  defp forward_chunk(state, %StreamChunk{type: :text_delta} = chunk), do: {[chunk], state}

  defp forward_chunk(%{config: config, iteration: iteration} = state, %StreamChunk{
         type: :reasoning_delta,
         reasoning: reasoning
       })
       when is_binary(reasoning) do
    emit_reasoning(config.telemetry_ctx, iteration + 1, reasoning)
    {[], state}
  end

  defp forward_chunk(state, _chunk), do: {[], state}

  @spec handle_complete_response(map(), LlmResponse.t()) :: {[StreamChunk.t()], map()}
  defp handle_complete_response(%{config: config, messages: messages, acc: acc} = state, response) do
    next_iteration = state.iteration + 1
    cost_infos = acc.cost_infos ++ List.wrap(response.cost_info)
    usage = add_usage(state.usage, response)

    case LlmResponse.function_calls(response) do
      calls when calls in [nil, []] ->
        emit_iteration(config.telemetry_ctx, next_iteration, response.cost_info, 0, true)
        acc = %{acc | cost_infos: cost_infos}
        {:ok, result} = finalize(response, messages, next_iteration, acc)
        done = done_chunk(response, usage, acc.cost_infos, result)

        {[done],
         %{state | phase: :done, status: :ok, iteration: next_iteration, usage: usage, acc: acc}}

      calls ->
        executed = execute_tool_calls(config, calls)

        emit_iteration(
          config.telemetry_ctx,
          next_iteration,
          response.cost_info,
          length(calls),
          false
        )

        acc = %{acc | cost_infos: cost_infos, function_calls: acc.function_calls ++ executed}

        tool_chunks =
          Enum.map(executed, fn call ->
            %StreamChunk{
              provider: response.provider,
              type: :tool_call,
              tool_calls: [call],
              metadata: %{iteration: next_iteration}
            }
          end)

        {tool_chunks,
         %{
           state
           | phase: :start_turn,
             messages: apply_tool_turn(config, messages, response, executed),
             iteration: next_iteration,
             usage: usage,
             acc: acc,
             collector: nil,
             cont: nil
         }}
    end
  end

  @spec finish_stream(map()) :: :ok
  defp finish_stream(%{config: config} = state) do
    metadata =
      config
      |> run_start_metadata()
      |> Map.merge(%{status: stop_status(state.status)})

    :telemetry.execute(
      [:llm_composer, :agent, :run, :stop],
      %{iterations: state.iteration},
      metadata
    )

    :ok
  end

  @spec terminate_error(map(), term()) :: {[StreamChunk.t()], map()}
  defp terminate_error(state, reason) do
    chunk = %StreamChunk{type: :error, metadata: %{reason: reason, status: :error}}
    {[chunk], %{state | phase: :done, status: :error}}
  end

  @spec done_chunk(LlmResponse.t(), StreamChunk.usage(), [CostInfo.t()], Result.t()) ::
          StreamChunk.t()
  defp done_chunk(response, usage, cost_infos, result) do
    %StreamChunk{
      provider: response.provider,
      type: :done,
      usage: usage,
      cost_info: StreamCollector.aggregate_cost_infos(cost_infos),
      metadata: %{agent_result: result, status: :ok}
    }
  end

  @spec provider_pricing_opts(config(), atom()) :: keyword()
  defp provider_pricing_opts(config, provider) do
    provider_mod = resolve_provider_module(config.settings, provider)

    config.settings
    |> provider_opts_for(provider_mod)
    |> Keyword.put_new(:track_costs, config.settings.track_costs)
  end

  @spec add_usage(map(), LlmResponse.t()) :: StreamChunk.usage()
  defp add_usage(usage, response) do
    input = (usage[:input_tokens] || 0) + (response.input_tokens || 0)
    output = (usage[:output_tokens] || 0) + (response.output_tokens || 0)

    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: input + output,
      cached_tokens: (usage[:cached_tokens] || 0) + (response.cached_tokens || 0),
      reasoning_tokens: (usage[:reasoning_tokens] || 0) + (response.reasoning_tokens || 0)
    }
  end

  @spec init_puller(Enumerable.t()) :: (term() -> term())
  defp init_puller(parsed) do
    reducer = fn chunk, _acc -> {:suspend, chunk} end
    fn command -> Enumerable.reduce(parsed, command, reducer) end
  end

  @spec pull((term() -> term())) :: {:chunk, StreamChunk.t(), (term() -> term())} | :done
  defp pull(cont) do
    case cont.({:cont, nil}) do
      {:suspended, chunk, next_cont} -> {:chunk, chunk, next_cont}
      {:done, _acc} -> :done
      {:halted, _acc} -> :done
    end
  end

  @spec stop_status(:running | :ok | :error) :: :halted | :ok | :error
  defp stop_status(:running), do: :halted
  defp stop_status(status), do: status

  # --- Tool execution ---

  @spec execute_tool_calls(config(), [FunctionCall.t()]) :: [FunctionCall.t()]
  defp execute_tool_calls(%{tool_execution: :parallel} = config, calls) do
    calls
    |> Task.async_stream(&execute_one(config, &1),
      ordered: true,
      timeout: config.tool_timeout,
      on_timeout: :kill_task
    )
    |> Enum.zip(calls)
    |> Enum.map(fn
      {{:ok, executed}, _call} -> executed
      {{:exit, reason}, call} -> error_call(call, {:execution_failed, inspect(reason)})
    end)
  end

  defp execute_tool_calls(config, calls) do
    Enum.map(calls, &execute_one(config, &1))
  end

  @spec execute_one(config(), FunctionCall.t()) :: FunctionCall.t()
  defp execute_one(config, %FunctionCall{} = call) do
    start_metadata =
      Map.merge(config.telemetry_ctx, %{
        name: call.name,
        arguments: call.arguments,
        metadata: call.metadata,
        id: call.id
      })

    :telemetry.span([:llm_composer, :agent, :tool], start_metadata, fn ->
      {executed, status} =
        case FunctionExecutor.execute(call, config.functions) do
          {:ok, executed} ->
            {executed, :ok}

          {:error, reason} ->
            Logger.warning(
              "[llm_composer.agent] tool_error name=#{call.name} reason=#{inspect(reason)}"
            )

            {error_call(call, reason), :error}
        end

      {executed, Map.merge(config.telemetry_ctx, %{name: call.name, id: call.id, status: status})}
    end)
  end

  @spec error_call(FunctionCall.t(), term()) :: FunctionCall.t()
  defp error_call(%FunctionCall{} = call, reason) do
    %FunctionCall{call | result: "Error: #{format_tool_error(reason)}"}
  end

  @spec format_tool_error(
          :function_not_found
          | {:execution_failed, String.t()}
          | {:invalid_arguments, String.t()}
        ) ::
          String.t()
  defp format_tool_error({:invalid_arguments, reason}), do: "invalid arguments (#{reason})"
  defp format_tool_error({:execution_failed, reason}), do: "execution failed (#{reason})"
  defp format_tool_error(:function_not_found), do: "unknown tool"

  # --- Telemetry helpers ---

  @spec emit_iteration(map(), non_neg_integer(), CostInfo.t() | nil, non_neg_integer(), boolean()) ::
          :ok
  defp emit_iteration(ctx, iteration, cost_info, tool_call_count, final?) do
    :telemetry.execute(
      [:llm_composer, :agent, :iteration, :stop],
      %{tool_call_count: tool_call_count},
      Map.merge(ctx, %{iteration: iteration, cost_info: cost_info, final: final?})
    )
  end

  @spec emit_reasoning(map(), non_neg_integer(), String.t()) :: :ok
  defp emit_reasoning(ctx, iteration, reasoning) do
    :telemetry.execute(
      [:llm_composer, :agent, :reasoning, :delta],
      %{},
      Map.merge(ctx, %{iteration: iteration, reasoning: reasoning})
    )
  end

  @spec run_measurements({:ok, Result.t()} | {:error, term()}) :: map()
  defp run_measurements({:ok, %Result{iterations: iterations}}), do: %{iterations: iterations}
  defp run_measurements({:error, _reason}), do: %{iterations: 0}

  @spec run_stop_metadata(map(), {:ok, Result.t()} | {:error, term()}) :: map()
  defp run_stop_metadata(metadata, {:ok, _result}), do: Map.put(metadata, :status, :ok)

  defp run_stop_metadata(metadata, {:error, reason}) do
    Map.merge(metadata, %{status: :error, reason: reason})
  end

  # --- Settings / message helpers ---

  @spec normalize_input(Settings.t(), input()) :: [Message.t()]
  defp normalize_input(settings, prompt) when is_binary(prompt) do
    [Message.new(:user, user_prompt(settings, prompt))]
  end

  defp normalize_input(_settings, messages) when is_list(messages), do: messages

  @spec user_prompt(Settings.t(), String.t()) :: String.t()
  defp user_prompt(%Settings{user_prompt_prefix: prefix}, message) do
    prefix <> message
  end

  @spec functions_from_settings(Settings.t()) :: [Function.t()]
  defp functions_from_settings(%Settings{providers: [{_mod, opts} | _]}) when is_list(opts) do
    Keyword.get(opts, :functions, [])
  end

  defp functions_from_settings(%Settings{provider_opts: opts}) when is_list(opts) do
    Keyword.get(opts, :functions, [])
  end

  defp functions_from_settings(_settings), do: []

  @spec resolve_provider_module(Settings.t(), atom()) :: module() | nil
  defp resolve_provider_module(settings, provider_atom) do
    settings
    |> configured_providers()
    |> Enum.find_value(fn {mod, _opts} ->
      if function_exported?(mod, :name, 0) and mod.name() == provider_atom, do: mod
    end)
  end

  @spec provider_opts_for(Settings.t(), module() | nil) :: keyword()
  defp provider_opts_for(settings, provider_mod) do
    settings
    |> configured_providers()
    |> Enum.find_value([], fn
      {^provider_mod, opts} -> opts || []
      _entry -> false
    end)
  end

  @spec configured_providers(Settings.t()) :: [{module(), keyword()}]
  defp configured_providers(%Settings{providers: providers}) when is_list(providers),
    do: providers

  defp configured_providers(%Settings{provider: nil}), do: []

  defp configured_providers(%Settings{provider: mod, provider_opts: opts}),
    do: [{mod, opts || []}]

  @spec last_user_message([Message.t()]) :: Message.t()
  defp last_user_message(messages) do
    Enum.reduce(messages, %Message{type: :user, content: ""}, fn
      %Message{type: :user} = msg, _acc -> msg
      _msg, acc -> acc
    end)
  end

  @spec new_acc() :: acc()
  defp new_acc, do: %{cost_infos: [], function_calls: []}
end
