defmodule LlmComposer.ProviderRouter.Simple do
  @moduledoc """

  ## Configuration

  Configuration is done via application environment:

  ```elixir
  config :llm_composer, :provider_router,
    backoff_ms: :timer.minutes(5),  # 5 minutes default
    block_on_errors: [
      {:status, 500..599},       # Server errors
      :timeout,                  # Request timeouts
      :econnrefused,            # Connection refused
      :network_error            # Generic network errors
    ]
  ```


  ## Behavior

  - **Success**: No action taken, provider remains available
  - **Failure**: If error matches configured patterns, provider is blocked for backoff period
  - **Blocking**: Blocked providers are skipped during provider selection
  - **Recovery**: Providers automatically become available after backoff period expires
  """

  @behaviour LlmComposer.ProviderRouter

  alias LlmComposer.Cache.Ets

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
      {:ok, {blocked_until, _failure_count}} ->
        if System.monotonic_time(:millisecond) < blocked_until do
          Logger.info("[#{provider.name()}] is currently blocked, skipping")
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
  Handle provider success. Currently no action is taken, but this could be
  extended to track success metrics or reset failure counters.
  """
  @impl LlmComposer.ProviderRouter
  def on_provider_success(provider, _resp, _metrics) do
    name = get_config(:name, __MODULE__)
    cache_mod().delete(provider, name)
    Logger.info("[#{provider.name()}] unblocked after success")
    :ok
  end

  @doc """
  Handle provider failure and determine if the provider should be blocked.

  If the error matches any of the configured blocking patterns, the provider
  will be blocked for the configured backoff duration.
  """
  @impl LlmComposer.ProviderRouter
  def on_provider_failure(provider, error, _metrics) do
    name = get_config(:name, __MODULE__)

    if should_block_error?(error) do
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
    else
      :continue
    end
  end

  # Private functions

  @spec should_block_error?(term()) :: boolean()
  defp should_block_error?(error) do
    block_patterns = get_config(:block_on_errors, default_block_patterns())

    Enum.any?(block_patterns, &match_error_pattern?(&1, error))
  end

  @spec default_block_patterns() :: list()
  defp default_block_patterns do
    [
      # Server errors
      {:status, 500..599},
      # Request timeouts
      :timeout,
      # Connection refused
      :econnrefused
    ]
  end

  @spec match_error_pattern?(term(), term()) :: boolean()
  defp match_error_pattern?({:status, range}, %{status: status}) when is_integer(status) do
    status in range
  end

  defp match_error_pattern?(:timeout, {:timeout, _}), do: true
  defp match_error_pattern?(:timeout, %{reason: :timeout}), do: true
  defp match_error_pattern?(:timeout, %{"error" => "timeout"}), do: true

  defp match_error_pattern?(:econnrefused, {:econnrefused, _}), do: true
  defp match_error_pattern?(:econnrefused, %{reason: :econnrefused}), do: true

  defp match_error_pattern?(pattern, error) when is_atom(pattern) and is_atom(error) do
    error == pattern
  end

  defp match_error_pattern?(pattern, error) when is_atom(pattern) and is_binary(error) do
    error
    |> String.downcase()
    |> String.contains?(Atom.to_string(pattern))
  end

  defp match_error_pattern?(_pattern, _error), do: false

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
end
