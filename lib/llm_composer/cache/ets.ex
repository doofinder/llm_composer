defmodule LlmComposer.Cache.Ets do
  @moduledoc """
  Basic ETS cache.
  """
  @behaviour LlmComposer.Cache.Behaviour

  use GenServer

  @type server :: atom() | module() | pid()

  @cleanup_interval :timer.minutes(5)

  # Client API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec get(binary, server) :: term()
  def get(key, server \\ __MODULE__) do
    GenServer.call(server, {:get, key})
  end

  @spec put(binary, term(), integer(), server) :: term()
  def put(key, value, ttl_seconds, server \\ __MODULE__) do
    GenServer.call(server, {:put, key, value, ttl_seconds})
  end

  @spec delete(binary, server) :: term()
  def delete(key, server \\ __MODULE__) do
    GenServer.call(server, {:delete, key})
  end

  @spec clear(server) :: term()
  def clear(server \\ __MODULE__) do
    GenServer.call(server, :clear)
  end

  # Server callbacks

  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, :cache_table)
    table = :ets.new(table_name, [:set, :protected, :named_table])

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)

    {:ok, %{table: table}}
  end

  @spec handle_call({atom, term} | {atom, term, term, pos_integer()}, reference(), map()) ::
          {atom, term, map()}
  def handle_call({:get, key}, _from, %{table: table} = state) do
    case :ets.lookup(table, key) do
      [{^key, value, expires_at}] ->
        if System.system_time(:second) < expires_at do
          {:reply, {:ok, value}, state}
        else
          :ets.delete(table, key)
          {:reply, :error, state}
        end

      [] ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:put, key, value, ttl_seconds}, _from, %{table: table} = state) do
    expires_at = System.system_time(:second) + ttl_seconds
    :ets.insert(table, {key, value, expires_at})
    {:reply, :ok, state}
  end

  def handle_call({:delete, key}, _from, %{table: table} = state) do
    :ets.delete(table, key)
    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, %{table: table} = state) do
    :ets.delete_all_objects(table)
    {:reply, :ok, state}
  end

  @spec handle_info(atom, map()) :: {:noreply, map()}
  def handle_info(:cleanup, %{table: table} = state) do
    current_time = System.system_time(:second)

    # Delete expired entries
    :ets.select_delete(table, [
      {{:"$1", :"$2", :"$3"}, [{:<, :"$3", current_time}], [true]}
    ])

    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)

    {:noreply, state}
  end
end
