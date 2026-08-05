defmodule Tursox.Manager do
  @moduledoc """
  Optional caller-supervised manager for many independent database pools.

  Managers are addressed by pid or caller-selected name. Tursox starts no
  singleton, registry, or dynamic atoms.
  """

  use GenServer

  alias Tursox.{Database, Error, Pool}

  @type id :: term()

  @doc "Starts an isolated manager."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "Atomically opens one owned database/pool entry."
  @spec open(GenServer.server(), id(), :memory | String.t(), keyword()) ::
          {:ok, pid()} | {:error, Error.t()}
  def open(manager, id, database, opts \\ []) do
    GenServer.call(manager, {:open, id, database, opts}, Keyword.get(opts, :timeout, 15_000))
  end

  @doc "Returns a pool pid or nil."
  def lookup(manager, id), do: GenServer.call(manager, {:lookup, id})

  @doc "Fetches a pool with an explicit not-found error."
  def fetch(manager, id) do
    case lookup(manager, id) do
      nil -> {:error, error(:manager_fetch, "database is not open", :not_found)}
      pool -> {:ok, pool}
    end
  end

  @doc "Lists safe entry metadata without options, SQL, values, or secrets."
  def list(manager), do: GenServer.call(manager, :list)

  @doc "Gracefully removes and closes one entry."
  def close(manager, id, opts \\ []) do
    GenServer.call(manager, {:close, id, opts}, Keyword.get(opts, :timeout, 15_000) + 1_000)
  end

  @doc "Stops the manager and drains every owned entry."
  def stop(manager, timeout \\ 15_000), do: GenServer.stop(manager, :normal, timeout)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with true <- is_list(opts) and Keyword.keyword?(opts),
         {:ok, max_databases} <- positive(opts, :max_databases, 100),
         {:ok, close_timeout} <- positive(opts, :close_timeout, 15_000) do
      {:ok,
       %{
         entries: %{},
         pools: %{},
         paths: %{},
         max_databases: max_databases,
         close_timeout: close_timeout
       }}
    else
      false -> {:stop, error(:manager_start, "manager options must be a keyword list")}
      {:error, error} -> {:stop, error}
    end
  end

  @impl true
  def handle_call({:open, id, database, opts}, _from, state) do
    with :ok <- validate_id(id),
         :ok <- ensure_new_id(state, id),
         :ok <- ensure_capacity(state),
         {:ok, canonical} <- canonical_path(database),
         :ok <- ensure_new_path(state, canonical),
         {:ok, pool} <- start_entry(database, opts) do
      entry = entry(id, database, canonical, pool, opts)
      state = put_entry(state, entry)
      emit(:open, entry, %{})
      {:reply, {:ok, pool}, state}
    else
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:lookup, id}, _from, state) do
    {:reply, get_in(state, [:entries, id, :pool]), state}
  end

  def handle_call(:list, _from, state) do
    entries =
      state.entries
      |> Map.values()
      |> Enum.map(&safe_metadata/1)
      |> Enum.sort_by(&inspect(&1.id))

    {:reply, entries, state}
  end

  def handle_call({:close, id, opts}, _from, state) do
    case Map.fetch(state.entries, id) do
      :error ->
        {:reply, {:error, error(:manager_close, "database is not open", :not_found)}, state}

      {:ok, entry} ->
        state = delete_entry(state, entry)
        timeout = Keyword.get(opts, :timeout, state.close_timeout)
        force? = Keyword.get(opts, :force, false)
        result = stop_pool(entry.pool, timeout, force?)
        Database.close(entry.database_resource)
        emit(:close, entry, %{forced: force?})
        {:reply, result, state}
    end
  end

  @impl true
  def handle_info({:EXIT, pool, reason}, state) do
    case Map.fetch(state.pools, pool) do
      :error ->
        {:noreply, state}

      {:ok, id} ->
        entry = Map.fetch!(state.entries, id)
        state = delete_entry(state, entry)
        Database.close(entry.database_resource)
        await_pool_down(entry.native_pool, state.close_timeout)
        emit(:crash, entry, %{reason: safe_reason(reason)})

        if entry.persistent? do
          case start_entry(entry.database, entry.start_options) do
            {:ok, restarted_pool} ->
              restarted =
                entry(
                  entry.id,
                  entry.database,
                  entry.canonical_path,
                  restarted_pool,
                  entry.start_options
                )

              emit(:restart, restarted, %{})
              {:noreply, put_entry(state, restarted)}

            {:error, error} ->
              emit(:restart_failed, entry, %{error_code: error.code})
              {:noreply, state}
          end
        else
          {:noreply, state}
        end
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.entries, fn {_id, entry} ->
      case stop_pool(entry.pool, state.close_timeout, false) do
        :ok -> :ok
        {:error, _error} -> stop_pool(entry.pool, state.close_timeout, true)
      end
    end)

    :ok
  end

  defp start_entry(database, opts) when is_list(opts) do
    pool_opts =
      opts
      |> Keyword.drop([:timeout, :force])
      |> Keyword.delete(:name)
      |> Keyword.put(:database, database)

    case Pool.start_link(pool_opts) do
      {:ok, pool} ->
        {:ok, pool}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, error(:manager_open, "pool failed to start: #{inspect(reason)}")}
    end
  end

  defp start_entry(_database, _opts),
    do: {:error, error(:manager_open, "entry options must be a keyword list")}

  defp entry(id, database, canonical, pool, opts) do
    database_options = Keyword.get(opts, :database_options, [])

    %{
      id: id,
      database: database,
      canonical_path: canonical,
      pool: pool,
      native_pool: Pool.pool(pool),
      database_resource: Pool.database(pool),
      pool_size: Keyword.get(opts, :pool_size, 1),
      journal_mode: Keyword.get(database_options, :journal_mode, :wal),
      persistent?: is_binary(database) and database != ":memory:",
      start_options: opts
    }
  end

  defp put_entry(state, entry) do
    %{
      state
      | entries: Map.put(state.entries, entry.id, entry),
        pools: Map.put(state.pools, entry.pool, entry.id),
        paths: put_path(state.paths, entry.canonical_path, entry.id)
    }
  end

  defp delete_entry(state, entry) do
    %{
      state
      | entries: Map.delete(state.entries, entry.id),
        pools: Map.delete(state.pools, entry.pool),
        paths: delete_path(state.paths, entry.canonical_path)
    }
  end

  defp put_path(paths, nil, _id), do: paths
  defp put_path(paths, path, id), do: Map.put(paths, path, id)
  defp delete_path(paths, nil), do: paths
  defp delete_path(paths, path), do: Map.delete(paths, path)

  defp safe_metadata(entry) do
    %{
      id: entry.id,
      path: entry.canonical_path || :memory,
      journal_mode: entry.journal_mode,
      pool_size: entry.pool_size,
      pool: entry.pool,
      persistent?: entry.persistent?
    }
  end

  defp canonical_path(database) when database in [:memory, ":memory:"], do: {:ok, nil}

  defp canonical_path(database) when is_binary(database) and byte_size(database) > 0,
    do: {:ok, Path.expand(database)}

  defp canonical_path(_database),
    do: {:error, error(:manager_open, "database must be :memory or a non-empty path")}

  defp validate_id(nil), do: {:error, error(:manager_open, "tenant id cannot be nil")}
  defp validate_id(_id), do: :ok

  defp ensure_new_id(state, id) do
    if Map.has_key?(state.entries, id),
      do: {:error, error(:manager_open, "tenant id is already open", :already_open)},
      else: :ok
  end

  defp ensure_capacity(state) do
    if map_size(state.entries) < state.max_databases,
      do: :ok,
      else: {:error, error(:manager_open, "manager capacity reached", :capacity)}
  end

  defp ensure_new_path(_state, nil), do: :ok

  defp ensure_new_path(state, path) do
    if Map.has_key?(state.paths, path),
      do:
        {:error, error(:manager_open, "canonical database path is already open", :path_conflict)},
      else: :ok
  end

  defp positive(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> {:error, error(:manager_start, "#{key} must be positive")}
    end
  end

  defp await_pool_down(pool, timeout) do
    if Process.alive?(pool) do
      monitor = Process.monitor(pool)

      receive do
        {:DOWN, ^monitor, :process, ^pool, _reason} -> :ok
      after
        timeout ->
          Process.demonitor(monitor, [:flush])
          Process.exit(pool, :kill)
      end
    end

    :ok
  end

  defp stop_pool(pool, _timeout, true) do
    Process.exit(pool, :kill)
    :ok
  end

  defp stop_pool(pool, timeout, false) do
    try do
      Pool.stop(pool, timeout)
      :ok
    rescue
      exception ->
        {:error,
         error(
           :manager_close,
           "pool did not drain: #{Exception.message(exception)}",
           :close_timeout
         )}
    catch
      :exit, reason ->
        {:error, error(:manager_close, "pool did not drain: #{inspect(reason)}", :close_timeout)}
    end
  end

  defp emit(event, entry, metadata) do
    :telemetry.execute(
      [:tursox, :manager, event],
      %{count: 1},
      Map.merge(%{id: entry.id, path: entry.canonical_path}, metadata)
    )
  end

  defp safe_reason(reason) when reason in [:normal, :shutdown, :killed], do: reason
  defp safe_reason(_reason), do: :abnormal

  defp error(operation, message, reason \\ nil) do
    %Error{
      code:
        if(reason in [:not_found, :capacity, :already_open, :path_conflict],
          do: :misuse,
          else: :invalid_argument
        ),
      operation: operation,
      message: message,
      metadata: if(reason, do: %{reason: reason}, else: %{})
    }
  end
end
