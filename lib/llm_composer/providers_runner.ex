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
        result = run_provider(selected_provider, messages, system_msg, provider_opts)

        case handle_provider_result(result, selected_provider, router) do
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
          module()
        ) :: {:cont, {:error, any()}} | {:halt, {:ok, any()}}
  defp handle_provider_result({:ok, _res} = ok_res, provider, router) do
    router.on_provider_success(provider, ok_res, %{})
    {:halt, ok_res}
  end

  defp handle_provider_result({:error, error} = err_res, provider, router) do
    Logger.warning("[#{provider.name()}] failed: #{inspect(error)}")
    router.on_provider_failure(provider, err_res, %{})
    {:cont, err_res}
  end

  @spec run_provider(module(), messages(), Message.t(), keyword()) ::
          {:ok, any()} | {:error, term()}
  defp run_provider(provider, messages, system_msg, provider_opts) do
    provider_name = provider.name()
    model = Keyword.fetch!(provider_opts, :model)

    :telemetry.span(
      [:llm_composer, :providers_runner, :call],
      %{provider: provider_name, model: model},
      fn ->
        result = provider.run(messages, system_msg, provider_opts)
        status = if match?({:ok, _}, result), do: :ok, else: :error
        {result, %{}, %{provider: provider_name, model: model, status: status}}
      end
    )
  end

  @spec get_provider_opts(keyword(), Settings.t()) :: keyword()
  defp get_provider_opts(opts, settings) do
    opts
    |> Keyword.put_new(:stream_response, settings.stream_response)
    |> Keyword.put_new(:track_costs, settings.track_costs)
    |> Keyword.put_new(:api_key, settings.api_key)
  end

  defp get_provider_router do
    :llm_composer
    |> Application.get_env(:provider_router, [])
    |> Keyword.get(:name, LlmComposer.ProviderRouter.Simple)
  end
end
