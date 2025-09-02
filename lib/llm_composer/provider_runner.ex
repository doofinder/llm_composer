defmodule LlmComposer.ProviderRunner do
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
  @spec run(messages(), Settings.t(), Message.t()) :: {:ok, any()} | {:error, atom()}
  def run(messages, %Settings{providers: providers} = settings, system_msg)
      when is_list(providers) and length(providers) > 1 do
    router = get_provider_router()

    if Process.whereis(router) == nil do
      {:error, :provider_router_not_started}
    else
      Enum.reduce_while(
        providers,
        {:error, :no_providers_available},
        &execute_provider_with_fallback(&1, &2, router, messages, system_msg, settings)
      )
    end
  end

  # Running only one provider.
  def run(messages, %Settings{providers: [{provider, provider_opts}]} = settings, system_msg) do
    provider_opts = get_provider_opts(provider_opts, settings)
    provider.run(messages, system_msg, provider_opts)
  end

  # old case, TODO: remove for llm_composer 0.10.0
  def run(
        messages,
        %Settings{provider: provider, provider_opts: provider_opts} = settings,
        system_msg
      )
      when provider != nil do
    provider_opts = get_provider_opts(provider_opts, settings)
    provider.run(messages, system_msg, provider_opts)
  end

  def run(_messages, %Settings{}, _system_msg) do
    {:error, :no_providers_configured}
  end

  defp execute_provider_with_fallback(
         {provider, provider_opts},
         _acc,
         router,
         messages,
         system_msg,
         settings
       ) do
    case router.should_use_provider?(provider) do
      :skip ->
        {:cont, {:error, :provider_skipped}}

      {:delay, _ms} ->
        {:cont, {:error, :provider_skipped}}

      :allow ->
        Logger.debug("#{provider.name()} allowed")
        provider_opts = get_provider_opts(provider_opts, settings)
        execute_provider(provider, messages, system_msg, provider_opts, router)
    end
  end

  defp execute_provider(provider, messages, system_msg, provider_opts, router) do
    {exec_time_us, result} =
      :timer.tc(fn ->
        provider.run(messages, system_msg, provider_opts)
      end)

    metrics = %{
      exec_time_milliseconds: exec_time_us / 1000
    }

    handle_provider_result(result, provider, router, metrics)
  end

  @spec handle_provider_result(
          {:ok, map()} | {:error, any()},
          module(),
          module(),
          map()
        ) :: {:cont, {:error, any()}} | {:halt, {:ok, any()}}
  defp handle_provider_result({:ok, %{status: status}}, provider, router, _metrics)
       when status >= 500 and status <= 599 do
    router.on_provider_failure(provider, {:server_error, status})
    {:cont, {:error, {:server_error, status}}}
  end

  defp handle_provider_result({:ok, _res} = ok_res, provider, router, metrics) do
    router.on_provider_success(provider, ok_res, metrics)
    {:halt, ok_res}
  end

  defp handle_provider_result({:error, error} = err_res, provider, router, _metrics) do
    router.on_provider_failure(provider, error)
    {:cont, err_res}
  end

  defp get_provider_opts(opts, settings) do
    Keyword.merge(opts,
      functions: settings.functions,
      stream_response: settings.stream_response,
      api_key: settings.api_key,
      track_costs: settings.track_costs
    )
  end

  defp get_provider_router do
    :llm_composer
    |> Application.get_env(:provider_router, [])
    |> Keyword.get(:name, LlmComposer.ProviderRouter.Simple)
  end
end
