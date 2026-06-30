defmodule LlmComposer.ProvidersRunner do
  @moduledoc """
  Handles provider execution logic including fallback strategies, routing,
  and error handling for multiple provider configurations.
  """

  alias LlmComposer.Message
  alias LlmComposer.Settings

  require Logger

  @type messages :: [Message.t()]

  @doc """
  Runs provider execution with fallback support for multiple providers.
  """
  @spec run(messages(), Settings.t(), Message.t()) :: {:ok, any()} | {:error, term()}
  def run(messages, %Settings{providers: [{provider, provider_opts}]} = settings, system_msg) do
    # only one provider, run it directly (still emitting telemetry).
    provider_opts = get_provider_opts(provider_opts, settings)
    {result, _metrics} = run_provider(provider, messages, system_msg, provider_opts)
    result
  end

  def run(messages, %Settings{providers: providers} = settings, system_msg)
      when is_list(providers) and length(providers) > 1 do
    router = get_provider_router()
    execute_with_fallback(router, providers, messages, system_msg, settings)
  end

  def run(_messages, %Settings{}, _system_msg) do
    {:error, :no_providers_configured}
  end

  @spec execute_with_fallback(
          module(),
          [{module(), keyword()}],
          messages(),
          Message.t(),
          Settings.t()
        ) ::
          {:ok, any()} | {:error, atom()}
  defp execute_with_fallback(router, all_providers, messages, system_msg, settings) do
    case router.select_provider(all_providers) do
      {:ok, {selected_provider, provider_opts}} ->
        provider_opts = get_provider_opts(provider_opts, settings)
        {result, metrics} = run_provider(selected_provider, messages, system_msg, provider_opts)

        case handle_provider_result(result, selected_provider, router, metrics) do
          {:halt, ok_res} ->
            ok_res

          {:cont, _err_res} ->
            execute_with_fallback(router, all_providers, messages, system_msg, settings)
        end

      :none_available ->
        {:error, :no_providers_available}
    end
  end

  @spec handle_provider_result(
          {:ok, map()} | {:error, any()},
          module(),
          module(),
          map()
        ) :: {:cont, {:error, any()}} | {:halt, {:ok, any()}}
  defp handle_provider_result({:ok, _res} = ok_res, provider, router, metrics) do
    router.on_provider_success(provider, ok_res, metrics)
    {:halt, ok_res}
  end

  defp handle_provider_result({:error, error} = err_res, provider, router, metrics) do
    Logger.warning(
      "[#{provider.name()}] failed (#{inspect(error)}) in #{Float.round(metrics.latency_ms, 2)} ms"
    )

    router.on_provider_failure(provider, err_res, metrics)
    {:cont, err_res}
  end

  @spec run_provider(module(), messages(), Message.t(), keyword()) ::
          {{:ok, any()} | {:error, term()}, map()}
  defp run_provider(provider, messages, system_msg, provider_opts) do
    provider_name = provider.name()
    # Intentional: telemetry must not raise on misconfiguration — nil is acceptable here.
    model = Keyword.get(provider_opts, :model)

    :telemetry.span(
      [:llm_composer, :providers_runner, :call],
      %{provider: provider_name, model: model},
      fn ->
        {exec_time_us, result} =
          :timer.tc(fn -> provider.run(messages, system_msg, provider_opts) end)

        status = if match?({:ok, _}, result), do: :ok, else: :error

        # metrics are still passed to the router callbacks to preserve the
        # behaviour relied on by custom routers; the span also exposes them.
        metrics = %{
          latency_ms: exec_time_us / 1000,
          status: status,
          provider: provider_name,
          model: model
        }

        {{result, metrics}, %{}, %{provider: provider_name, model: model, status: status}}
      end
    )
  end

  @spec get_provider_opts(keyword(), Settings.t()) :: keyword()
  defp get_provider_opts(opts, settings) do
    opts
    |> Keyword.put_new(:stream_response, settings.stream_response)
    |> Keyword.put_new(:track_costs, settings.track_costs)
    |> Keyword.put_new(:api_key, settings.api_key)
    |> maybe_put_sse_middleware(settings)
  end

  defp maybe_put_sse_middleware(opts, %{sse_middleware: nil}), do: opts
  defp maybe_put_sse_middleware(opts, %{sse_middleware: middleware}), do: Keyword.put_new(opts, :sse_middleware, middleware)

  defp get_provider_router do
    :llm_composer
    |> Application.get_env(:provider_router, [])
    |> Keyword.get(:name, LlmComposer.ProviderRouter.Simple)
  end
end
