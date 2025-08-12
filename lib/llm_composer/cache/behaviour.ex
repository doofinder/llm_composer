defmodule LlmComposer.Cache.Behaviour do
  @moduledoc """
  Cache behaviour to use other implementations for cache mod.
  """

  @doc """
  Retrieves a value from the cache by key.
  Returns `{:ok, value}` if found and not expired, `:miss` otherwise.
  """
  @callback get(key :: term()) :: {:ok, term()} | :miss

  @doc """
  Stores a value in the cache with the given key and TTL in seconds.
  Returns `:ok`.
  """
  @callback put(key :: term(), value :: term(), ttl_seconds :: non_neg_integer()) :: :ok

  @doc """
  Deletes a key from the cache.
  Returns `:ok`.
  """
  @callback delete(key :: term()) :: :ok

  @doc """
  Clears all entries from the cache.
  Returns `:ok`.
  """
  @callback clear() :: :ok

  @doc """
  Starts the cache process.
  """
  @callback start_link(opts :: keyword()) :: GenServer.on_start()
end
