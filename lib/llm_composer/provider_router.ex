defmodule LlmComposer.ProviderRouter do
  @moduledoc """
  Behaviour for implementing provider routing strategies.

  Allows customization of how providers are selected and how failures are handled.
  This enables users to implement custom logic for provider failover, circuit breaking,
  load balancing, or any other routing strategy.

  ## Example Usage

  ```elixir
  defmodule MyApp.CustomRouter do
    @behaviour LlmComposer.ProviderRouter

    def should_use_provider?(provider) do
      # Custom logic to determine if provider should be used
      if provider_is_healthy?(provider) do
        :allow
      else
        :skip
      end
    end

    def on_provider_success(provider, _ok_resp, _metrics) do
      # Track successful requests, reset failure counters, etc.
      :ok
    end

    def on_provider_failure(provider, error, _metrics) do
      # Decide how to handle the failure
      case error do
        %{status: status} when status >= 500 -> :block
        _ -> :continue
      end
    end
  end
  ```
  """

  @type provider :: module() | atom()
  @type error :: term()
  @type ok_res :: {:ok, Tesla.Env.t()}
  @type metrics :: map()
  @type routing_decision :: :allow | :skip
  @type failure_response :: :continue | :block | {:block, non_neg_integer()}

  @doc """
  Called before attempting to use a provider.

  This callback allows the router to decide whether a provider should be used
  based on its current state, recent failures, load, or any other criteria.

  ## Returns
  - `:allow` - proceed with this provider
  - `:skip` - skip this provider and try the next one

  ## Parameters
  - `provider` - The provider module that is about to be used
  """
  @callback should_use_provider?(provider()) :: routing_decision()

  @doc """
  Called when a provider successfully handles a request.

  This callback can be used to:
  - Reset failure counters
  - Update success metrics
  - Adjust provider weights
  - Close circuit breakers
  - Log successful interactions

  ## Parameters
  - `provider` - The provider module that succeeded
  """
  @callback on_provider_success(provider(), ok_res(), metrics()) :: :ok

  @doc """
  Called when a provider fails to handle a request.

  This callback allows the router to decide how to handle the failure
  and whether the provider should be temporarily blocked.

  ## Returns
  - `:continue` - mark the failure but keep the provider available for future requests
  - `:block` - temporarily block this provider (using default blocking duration)
  - `{:block, ms}` - block the provider for a specific duration in milliseconds

  ## Parameters
  - `provider` - The provider module that failed
  - `error` - The error returned by the provider
  """
  @callback on_provider_failure(provider(), error(), map()) :: failure_response()

  @doc """
  Starts the process linked to the current process.

  This callback is optional. If implemented, it should start the process with the given arguments
  and return `{:ok, pid}` on success or `{:error, reason}` on failure.

  ## Parameters

    - `args`: The arguments required to start the process.

  ## Returns

    - `{:ok, pid}` when the process is successfully started and linked.
    - `{:error, reason}` if the process could not be started.

  Implement this callback to support supervised or linked process initialization for your module.
  """
  @callback start_link(args :: term()) :: {:ok, pid()} | {:error, term()}

  @doc """
  Optional callback to initialize any resources needed by the router.

  This is called once when the router is first used and can be used to:
  - Initialize ETS tables
  - Start monitoring processes
  - Set up any required state

  If not implemented, no initialization is performed.
  """
  @callback init(otps :: keyword()) :: :ok

  @doc """
  Optional callback to clean up resources when the router is no longer needed.

  This can be used to:
  - Clean up ETS tables
  - Stop monitoring processes
  - Release any held resources

  If not implemented, no cleanup is performed.
  """
  @callback cleanup() :: :ok

  @optional_callbacks [init: 1, cleanup: 0, start_link: 1]
end
