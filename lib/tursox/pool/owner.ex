defmodule Tursox.Pool.Owner do
  @moduledoc false

  use GenServer

  alias Tursox.{Database, Error}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  def pool(owner), do: GenServer.call(owner, :pool)
  def metadata(owner), do: GenServer.call(owner, :metadata)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    registry = :ets.new(:tursox_pool_resources, [:set, :public])

    with {:ok, database, owned?} <- database(opts),
         {:ok, pool} <- start_pool(database, opts, registry) do
      {:ok, %{database: database, owned?: owned?, pool: pool, registry: registry, monitors: %{}}}
    else
      {:error, error} -> {:stop, error}
    end
  end

  @impl true
  def handle_call(:pool, _from, state), do: {:reply, state.pool, state}

  def handle_call(:metadata, _from, state) do
    state = sweep_dead_workers(state)

    {:reply,
     %{
       database: Database.metadata(state.database),
       owned?: state.owned?,
       pool: state.pool
     }, state}
  end

  @impl true
  def handle_info({:track_worker, worker}, state) do
    if Map.has_key?(state.monitors, worker) do
      {:noreply, state}
    else
      monitor = Process.monitor(worker)
      {:noreply, %{state | monitors: Map.put(state.monitors, worker, monitor)}}
    end
  end

  def handle_info({:DOWN, _monitor, :process, worker, _reason}, state) do
    cleanup_worker(state.registry, worker)
    {:noreply, %{state | monitors: Map.delete(state.monitors, worker)}}
  end

  def handle_info({:EXIT, pool, reason}, %{pool: pool} = state),
    do: {:stop, {:pool_exit, reason}, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if Process.alive?(state.pool) do
      Supervisor.stop(state.pool, :normal, 15_000)
    end

    cleanup_all(state.registry)
    if state.owned?, do: Database.close(state.database)
    :ok
  end

  defp database(opts) do
    case Keyword.get(opts, :database, :memory) do
      %Database{} = database ->
        {:ok, database, Keyword.get(opts, :own_database, false)}

      path ->
        case Database.open(path, Keyword.get(opts, :database_options, [])) do
          {:ok, database} -> {:ok, database, true}
          {:error, error} -> {:error, error}
        end
    end
  end

  defp start_pool(database, opts, registry) do
    pool_opts =
      opts
      |> Keyword.take(Elixir.DBConnection.available_start_options())
      |> Keyword.delete(:name)
      |> Keyword.put(:database, database)
      |> Keyword.put(:busy_timeout, Keyword.get(opts, :busy_timeout, 0))
      |> Keyword.put(:resource_registry, registry)
      |> Keyword.put(:resource_owner, self())

    case Elixir.DBConnection.start_link(Tursox.DBConnection, pool_opts) do
      {:ok, pool} ->
        {:ok, pool}

      {:error, reason} ->
        if not match?(%Database{}, Keyword.get(opts, :database)) or
             Keyword.get(opts, :own_database, false) do
          Database.close(database)
        end

        {:error, normalize_error(reason)}
    end
  end

  defp sweep_dead_workers(state) do
    Enum.reduce(state.monitors, state, fn {worker, monitor}, state ->
      if Process.alive?(worker) do
        state
      else
        Process.demonitor(monitor, [:flush])
        cleanup_worker(state.registry, worker)
        %{state | monitors: Map.delete(state.monitors, worker)}
      end
    end)
  end

  defp cleanup_worker(registry, worker) do
    registry
    |> :ets.match_object({{worker, :_, :_}, :_})
    |> cleanup_entries()
  end

  defp cleanup_all(registry), do: registry |> :ets.tab2list() |> cleanup_entries()

  defp cleanup_entries(entries) do
    entries
    |> Enum.sort_by(fn {_key, {kind, _resource}} -> cleanup_order(kind) end)
    |> Enum.each(fn
      {_key, {:cursor, resource}} -> Tursox.Cursor.close(resource)
      {_key, {:statement, resource}} -> Tursox.Statement.close(resource)
      {_key, {:connection, resource}} -> Tursox.Connection.close(resource)
    end)
  end

  defp cleanup_order(:cursor), do: 0
  defp cleanup_order(:statement), do: 1
  defp cleanup_order(:connection), do: 2

  defp normalize_error(%_{} = exception), do: exception

  defp normalize_error(reason) do
    %Error{
      code: :internal,
      operation: :pool_start,
      message: "pool failed to start: #{inspect(reason)}"
    }
  end
end
