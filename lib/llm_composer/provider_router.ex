defmodule LlmComposer.ProviderRouter do
  @moduledoc """
  Behaviour for implementing provider routing strategies.

  Allows customization of how providers are selected and how failures are handled.
  This enables users to implement custom logic for provider failover, circuit breaking,
  load balancing, or any other routing strategy.

  ## Example Usage

  ```elixir
  defmodule MyApp.SimpleRouter do
    @behaviour LlmComposer.ProviderRouter

    @impl true
    def on_provider_success(_provider, _response, _metrics) do
      # Could log success metrics here
      :ok
    end

    @impl true
    def on_provider_failure(_provider, error, _metrics) do
      # Block on server errors, continue on client errors
      case error do
        %{status: status} when status >= 500 -> :block
        _ -> :continue
      end
    end

    @impl true
    def select_provider(providers) when length(providers) > 0 do
      # Simple random selection
      {provider, opts} = Enum.random(providers)
      {:ok, {provider, opts}}
    end

    def select_provider([]), do: :none_available
  end
  ```
  """

  @type error :: term()
  @type failure_response :: :block
  @type metrics :: map()
  @type ok_res :: {:ok, Tesla.Env.t()}
  @type provider :: module() | atom()
  @type providers :: [{provider(), keyword()}]

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
  - `:block` - temporarily block this provider (using default blocking duration)

  ## Parameters
  - `provider` - The provider module that failed
  - `error` - The error returned by the provider
  """
  @callback on_provider_failure(provider(), error(), map()) :: failure_response()

  @doc """
  Selects an eligible provider from the given list.

  This callback allows the router to implement custom logic for selecting the
  next provider to use, potentially based on health, load, or other criteria.

  ## Returns
  - `{:ok, provider}` - The selected provider module.
  - `:none_available` - No eligible providers are currently available.

  ## Parameters
  - `providers` - A list of `{:provider_module, provider_opts}` tuples.
  """
  @callback select_provider(providers :: providers()) ::
              {:ok, {provider(), keyword()}} | :none_available

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
