defmodule LlmComposer.ProvidersRunner do
  @moduledoc """
  Handles provider execution logic including fallback strategies, routing,
  and error handling for multiple provider configurations.
  """

  alias LlmComposer.LlmResponse
  alias LlmComposer.Message
  alias LlmComposer.Settings

  require Logger

  @type messages :: [Message.t()]

  @doc """
  Runs provider execution with fallback support for multiple providers.
  """
  @spec run(messages(), Settings.t(), Message.t()) :: {:ok, any()} | {:error, atom()}
  def run(messages, %Settings{providers: [{provider, provider_opts}]} = settings, system_msg) do
    # only one provider, directly run it.
    provider_opts = get_provider_opts(provider_opts, settings)
    provider.run(messages, system_msg, provider_opts)
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

        {exec_time_us, result} =
          :timer.tc(fn ->
            selected_provider.run(messages, system_msg, provider_opts)
          end)

        metrics = build_metrics(result, exec_time_us, selected_provider, provider_opts)
        Logger.debug("#{selected_provider.name()} metrics: #{inspect(metrics)}")

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
    # if failure, we continue with next provider if any
    {:cont, err_res}
  end

  @spec get_provider_opts(keyword(), Settings.t()) :: keyword()
  defp get_provider_opts(opts, settings) do
    opts
    |> Keyword.put_new(:functions, settings.functions)
    |> Keyword.put_new(:stream_response, settings.stream_response)
    |> Keyword.put_new(:track_costs, settings.track_costs)
    |> Keyword.put_new(:api_key, settings.api_key)
  end

  defp get_provider_router do
    :llm_composer
    |> Application.get_env(:provider_router, [])
    |> Keyword.get(:name, LlmComposer.ProviderRouter.Simple)
  end

  @spec build_metrics({:ok, LlmResponse.t()} | {:error, term()}, number(), module(), keyword()) ::
          map()
  defp build_metrics(result, exec_time_us, provider, provider_opts) do
    latency_ms = exec_time_us / 1000

    status =
      case result do
        {:ok, _} -> :ok
        {:error, _error} -> :error
      end

    %{
      latency_ms: latency_ms,
      status: status,
      provider: provider.name(),
      model: Keyword.fetch!(provider_opts, :model)
    }
  end
end
