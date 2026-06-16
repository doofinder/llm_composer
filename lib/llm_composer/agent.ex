defmodule LlmComposer.Agent do
  @moduledoc """
  Runs an agentic tool-calling loop on top of `LlmComposer.run_completion/3`.

  Where `LlmComposer.simple_chat/2` and `LlmComposer.run_completion/3` perform a single model
  turn, `LlmComposer.Agent.run/3` automates the full cycle:

      ask → model requests tool calls → execute them → feed the results back → repeat
            → until the model returns a final, tool-free answer.

  The loop is pure orchestration over existing building blocks
  (`LlmComposer.FunctionExecutor`, `LlmComposer.FunctionCallHelpers`) and does not change any
  provider behaviour. It is **synchronous** — streaming is not supported in this version.

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

  The loop emits the following `:telemetry` events:

  - `[:llm_composer, :agent, :run, :start | :stop | :exception]` — the whole run. The `:stop`
    event includes an `:iterations` measurement and a `:status` (`:ok`/`:error`) metadata key.
  - `[:llm_composer, :agent, :iteration, :stop]` — one per model turn. Measurement
    `:tool_call_count`; metadata `:iteration`, `:cost_info`, `:final`.
  - `[:llm_composer, :agent, :tool, :start | :stop | :exception]` — one per tool execution.
    Metadata `:name` and (on stop) `:status` (`:ok`/`:error`).
  """

  alias LlmComposer.Agent.Result
  alias LlmComposer.CostInfo
  alias LlmComposer.Function
  alias LlmComposer.FunctionCall
  alias LlmComposer.FunctionCallHelpers
  alias LlmComposer.FunctionExecutor
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message
  alias LlmComposer.Settings

  require Logger

  @default_max_iterations 10

  @type input() :: String.t() | [Message.t()]

  @type run_opts() :: [
          max_iterations: pos_integer(),
          functions: [Function.t()],
          tool_execution: :sequential | :parallel,
          tool_timeout: timeout()
        ]

  @typep config() :: %{
           settings: Settings.t(),
           functions: [Function.t()],
           max_iterations: pos_integer(),
           tool_execution: :sequential | :parallel,
           tool_timeout: timeout()
         }

  @typep acc() :: %{cost_infos: [CostInfo.t()], function_calls: [FunctionCall.t()]}

  @doc """
  Runs the agentic tool-calling loop until the model returns a final, tool-free response.

  Accepts either a user prompt string (wrapped into a `:user` message, honouring the settings'
  `:user_prompt_prefix`) or an explicit list of `LlmComposer.Message.t()`.

  Returns `{:ok, %LlmComposer.Agent.Result{}}` on success, or `{:error, reason}` where `reason`
  may be `:max_iterations_reached`, `:streaming_not_supported`, or any error returned by the
  underlying provider.

  See the module documentation for the available options.
  """
  @spec run(Settings.t(), input(), run_opts()) :: {:ok, Result.t()} | {:error, term()}
  def run(settings, input, opts \\ [])

  def run(%Settings{stream_response: true}, _input, _opts), do: {:error, :streaming_not_supported}

  def run(%Settings{} = settings, input, opts) do
    functions = Keyword.get(opts, :functions) || functions_from_settings(settings)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)

    config = %{
      settings: settings,
      functions: functions,
      max_iterations: max_iterations,
      tool_execution: Keyword.get(opts, :tool_execution, :sequential),
      tool_timeout: Keyword.get(opts, :tool_timeout, :infinity)
    }

    messages = normalize_input(settings, input)
    start_metadata = %{max_iterations: max_iterations, tool_count: length(functions)}

    :telemetry.span([:llm_composer, :agent, :run], start_metadata, fn ->
      result = loop(config, messages, 0, new_acc())
      {result, run_measurements(result), run_stop_metadata(start_metadata, result)}
    end)
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
        emit_iteration(next_iteration, response.cost_info, 0, true)
        finalize(response, messages, next_iteration, %{acc | cost_infos: cost_infos})

      calls ->
        executed = execute_tool_calls(config, calls)
        emit_iteration(next_iteration, response.cost_info, length(calls), false)

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

        loop(
          config,
          messages ++ [assistant_msg | tool_msgs],
          next_iteration,
          %{acc | cost_infos: cost_infos, function_calls: acc.function_calls ++ executed}
        )
    end
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
    :telemetry.span([:llm_composer, :agent, :tool], %{name: call.name}, fn ->
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

      {executed, %{name: call.name, status: status}}
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

  @spec emit_iteration(non_neg_integer(), CostInfo.t() | nil, non_neg_integer(), boolean()) :: :ok
  defp emit_iteration(iteration, cost_info, tool_call_count, final?) do
    :telemetry.execute(
      [:llm_composer, :agent, :iteration, :stop],
      %{tool_call_count: tool_call_count},
      %{iteration: iteration, cost_info: cost_info, final: final?}
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
  defp user_prompt(%Settings{user_prompt_prefix: prefix}, message) when is_binary(prefix) do
    prefix <> message
  end

  defp user_prompt(_settings, message), do: message

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
