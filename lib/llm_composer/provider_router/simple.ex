defmodule LlmComposer.ProviderRouter.Simple do
  @moduledoc """
  Simple provider router that implements exponential backoff for failed providers.

  This router blocks providers that encounter specific types of errors for a configurable
  backoff period. The backoff duration increases exponentially with each consecutive failure,
  helping to avoid overwhelming failing services while allowing for automatic recovery.

  ## Configuration

  Configuration is done via application environment:

  ```elixir
  config :llm_composer, :provider_router,
    min_backoff_ms: 1_000,                    # 1 second minimum backoff (default)
    max_backoff_ms: :timer.minutes(5),        # 5 minutes maximum backoff (default)
    cache_mod: LlmComposer.Cache.Ets,         # Cache module to use (default)
    cache_opts: [                             # Cache options (default shown below)
      name: LlmComposer.ProviderRouter.Simple,
      table_name: :llm_composer_provider_blocks
    ],
    name: LlmComposer.ProviderRouter.Simple   # Router instance name (default)
  ```

  ## Backoff Strategy

  The router uses exponential backoff with the following formula:
  ```
  backoff_ms = min(max_backoff_ms, min_backoff_ms * 2^(failure_count - 1))
  ```

  Examples with default settings:
  - 1st failure: 1 second
  - 2nd failure: 2 seconds
  - 3rd failure: 4 seconds
  - 4th failure: 8 seconds
  - 5th failure: 16 seconds
  - ...continuing until max_backoff_ms (5 minutes)

  ## Behavior

  - **Success**: Provider is unblocked and failure count is reset
  - **Failure**: Provider is blocked for exponential backoff period
  - **Blocking**: Blocked providers are skipped during provider selection
  - **Recovery**: Providers automatically become available after backoff period expires
  - **Persistence**: Blocking state persists across application restarts (stored in ETS with long TTL)
  """

  @behaviour LlmComposer.ProviderRouter

  require Logger

  @table_name Application.compile_env(
                :llm_composer,
                :provider_router_ets_table,
                :llm_composer_provider_blocks
              )

  @long_ttl_seconds :timer.hours(24) * 10

  @doc """
  Initialize the ETS table for storing provider blocking state.
  """
  @impl LlmComposer.ProviderRouter
  def start_link(opts) do
    mod = cache_mod()
    opts = Keyword.merge(cache_opts(), opts)
    mod.start_link(opts)
  end

  @doc """
  Check if a provider should be used based on its blocking state.

  Returns `:skip` if the provider is currently blocked due to recent failures,
  `:allow` otherwise.
  """
  @impl LlmComposer.ProviderRouter
  def should_use_provider?(provider) do
    name = get_config(:name, __MODULE__)

    case cache_mod().get(provider, name) do
      {:ok, {blocked_until, failure_count}} ->
        if System.monotonic_time(:millisecond) < blocked_until do
          maybe_log(provider.name(), failure_count)
          :skip
        else
          # Here we do not remove the data in ETS, this will be removed on success,
          # or will be increased if fails remains
          :allow
        end

      _ ->
        :allow
    end
  end

  @doc """
  Handle provider success by unblocking the provider and resetting its failure count.

  This removes any blocking state for the provider, allowing it to be used immediately
  for future requests.
  """
  @impl LlmComposer.ProviderRouter
  def on_provider_success(provider, _resp, _metrics) do
    name = get_config(:name, __MODULE__)

    case cache_mod().get(provider, name) do
      :miss ->
        # Provider was not blocked, no action needed, and no log
        :ok

      _ ->
        # Provider was blocked, so unblock it and log
        cache_mod().delete(provider, name)
        Logger.info("[#{provider.name()}] unblocked after success")
        :ok
    end
  end

  @doc """
  Handle provider failure and determine if the provider should be blocked.

  The provider will be blocked for the configured backoff duration.
  """
  @impl LlmComposer.ProviderRouter
  def on_provider_failure(provider, error, _metrics) do
    name = get_config(:name, __MODULE__)

    min_backoff_ms = get_config(:min_backoff_ms, 1_000)
    max_backoff_ms = get_config(:max_backoff_ms, :timer.minutes(5))

    current_state = cache_mod().get(provider, name)

    failure_count =
      case current_state do
        {:ok, {_blocked_until, count}} when is_integer(count) -> count + 1
        _ -> 1
      end

    backoff_ms =
      min(max_backoff_ms, round(min_backoff_ms * :math.pow(2, failure_count - 1)))

    blocked_until = System.monotonic_time(:millisecond) + backoff_ms

    cache_mod().put(provider, {blocked_until, failure_count}, @long_ttl_seconds, name)

    Logger.info(
      "[#{provider.name()}] blocked for #{backoff_ms} ms due to error #{inspect(error)}"
    )

    {:block, backoff_ms}
  end

  @doc """
  Selects an eligible provider from the given list.

  This implementation iterates through the providers and returns the first one
  that is not currently blocked by the circuit breaker.
  """
  @impl LlmComposer.ProviderRouter
  def select_provider(providers) do
    Enum.find_value(providers, fn {provider_module, opts} ->
      case should_use_provider?(provider_module) do
        :allow -> {:ok, {provider_module, opts}}
        :skip -> nil
      end
    end) || :none_available
  end

  # Private functions
  @spec get_config(atom(), term()) :: term()
  defp get_config(key, default) do
    :llm_composer
    |> Application.get_env(:provider_router, [])
    |> Keyword.get(key, default)
  end

  @spec cache_mod() :: module()
  defp cache_mod do
    get_config(:cache_mod, LlmComposer.Cache.Ets)
  end

  @spec cache_opts() :: keyword()
  defp cache_opts do
    get_config(:cache_opts, name: __MODULE__, table_name: @table_name)
  end

  @spec maybe_log(atom(), integer()) :: :ok
  defp maybe_log(provider_name, count) do
    if count < 3 do
      Logger.info("[#{provider_name}] is currently blocked, skipping")
    end

    :ok
  end
end
