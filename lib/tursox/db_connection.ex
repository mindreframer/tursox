defmodule Tursox.DBConnection do
  @moduledoc false

  use DBConnection

  alias Tursox.{Connection, Cursor, Database, Error, Query, Result, Statement}

  defstruct [:connection, :registry, :worker, prepared: %{}]

  @fatal_codes [:io, :corrupt, :closed]

  @impl true
  def connect(opts) do
    with %Database{} = database <- Keyword.get(opts, :database),
         {:ok, connection} <-
           Database.connect(database, busy_timeout: Keyword.get(opts, :busy_timeout, 0)) do
      registry = Keyword.fetch!(opts, :resource_registry)
      worker = self()
      track(registry, worker, :connection, connection)
      send(Keyword.fetch!(opts, :resource_owner), {:track_worker, worker})
      {:ok, %__MODULE__{connection: connection, registry: registry, worker: worker}}
    else
      nil -> {:error, invalid("pool requires one shared database resource")}
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  def disconnect(_error, %__MODULE__{} = state) do
    Enum.each(state.prepared, fn {_ref, statement} ->
      Statement.close(statement)
      untrack(state, :statement, statement.resource)
    end)

    Connection.close(state.connection)
    untrack(state, :connection, state.connection.resource)
    :ok
  end

  @impl true
  def checkout(state), do: {:ok, state}

  @impl true
  def ping(%__MODULE__{} = state) do
    case Connection.pragma_query(state.connection, :user_version) do
      {:ok, _rows} -> {:ok, state}
      {:error, error} -> {:disconnect, error, state}
    end
  end

  @impl true
  def handle_status(_opts, %__MODULE__{} = state) do
    case Connection.status(state.connection) do
      {:ok, status} -> {status, state}
      {:error, error} -> {:disconnect, error, state}
    end
  end

  @impl true
  def handle_begin(opts, %__MODULE__{} = state) do
    case Connection.begin(state.connection, mode: Keyword.get(opts, :mode, :deferred)) do
      :ok ->
        {:ok, %Result{}, state}

      {:error, %Error{code: code}} when code in [:busy, :busy_snapshot, :misuse] ->
        {:transaction, state}

      {:error, error} ->
        {:disconnect, error, state}
    end
  end

  @impl true
  def handle_commit(_opts, %__MODULE__{} = state) do
    case Connection.commit(state.connection) do
      :ok ->
        {:ok, %Result{}, state}

      {:error, %Error{code: code}} when code in [:busy, :busy_snapshot, :misuse] ->
        {:transaction, state}

      {:error, error} ->
        {:disconnect, error, state}
    end
  end

  @impl true
  def handle_rollback(_opts, %__MODULE__{} = state) do
    case Connection.rollback(state.connection) do
      :ok -> {:ok, %Result{}, state}
      {:error, %Error{code: :misuse}} -> {:idle, state}
      {:error, error} -> {:disconnect, error, state}
    end
  end

  @impl true
  def handle_prepare(%Query{} = query, _opts, %__MODULE__{} = state) do
    case ensure_prepared(query, state) do
      {:ok, _statement, state} -> {:ok, query, state}
      {:error, error, state} -> error_result(error, state)
    end
  end

  @impl true
  def handle_execute(%Query{} = query, params, opts, %__MODULE__{} = state) do
    case ensure_prepared(query, state) do
      {:ok, statement, state} -> execute_prepared(query, statement, params, opts, state)
      {:error, error, state} -> error_result(error, state)
    end
  end

  @impl true
  def handle_close(%Query{} = query, _opts, %__MODULE__{} = state) do
    {statement, prepared} = Map.pop(state.prepared, query.ref)

    if statement do
      Statement.close(statement)
      untrack(state, :statement, statement.resource)
    end

    {:ok, %Result{}, %{state | prepared: prepared}}
  end

  @impl true
  def handle_declare(%Query{command: :query} = query, params, _opts, %__MODULE__{} = state) do
    with {:ok, statement, state} <- ensure_prepared(query, state),
         {:ok, cursor} <- Statement.query(statement, params) do
      track(state.registry, state.worker, :cursor, cursor)
      {:ok, query, cursor, state}
    else
      {:error, error, state} -> error_result(error, state)
      {:error, error} -> error_result(error, state)
    end
  end

  def handle_declare(%Query{}, _params, _opts, %__MODULE__{} = state) do
    {:error, invalid("only query commands can declare cursors"), state}
  end

  @impl true
  def handle_fetch(_query, %Cursor{} = cursor, opts, %__MODULE__{} = state) do
    chunk_size = Keyword.get(opts, :chunk_size, 500)

    case Cursor.fetch(cursor, chunk_size) do
      {:rows, rows} ->
        {:cont, %Result{columns: cursor.columns, rows: rows, num_rows: length(rows)}, state}

      {:done, rows} ->
        untrack(state, :cursor, cursor.resource)
        {:halt, %Result{columns: cursor.columns, rows: rows, num_rows: length(rows)}, state}

      :done ->
        untrack(state, :cursor, cursor.resource)
        {:halt, %Result{columns: cursor.columns, rows: [], num_rows: 0}, state}

      {:error, error} ->
        error_result(error, state)
    end
  end

  @impl true
  def handle_deallocate(_query, %Cursor{} = cursor, _opts, %__MODULE__{} = state) do
    Cursor.close(cursor)
    untrack(state, :cursor, cursor.resource)
    {:ok, %Result{}, state}
  end

  defp execute_prepared(%Query{command: :execute} = query, statement, params, _opts, state) do
    case Statement.execute(statement, params) do
      {:ok, result} -> success(query, result, state)
      {:error, error} -> error_result(error, state)
    end
  end

  defp execute_prepared(%Query{command: :query} = query, statement, params, opts, state) do
    max_rows = Keyword.get(opts, :max_rows, 10_000)
    fetch_size = min(Keyword.get(opts, :chunk_size, 500), max(max_rows + 1, 1))

    with {:ok, cursor} <- Statement.query(statement, params),
         {:ok, result} <- Cursor.all(cursor, max_rows, fetch_size) do
      success(query, result, state)
    else
      {:error, error} -> error_result(error, state)
    end
  end

  defp success(%Query{persistent: true} = query, result, state),
    do: {:ok, query, result, state}

  defp success(%Query{} = query, result, state) do
    {statement, prepared} = Map.pop(state.prepared, query.ref)

    if statement do
      Statement.close(statement)
      untrack(state, :statement, statement.resource)
    end

    {:ok, query, result, %{state | prepared: prepared}}
  end

  defp ensure_prepared(%Query{ref: ref} = query, %__MODULE__{} = state) do
    case Map.fetch(state.prepared, ref) do
      {:ok, statement} ->
        {:ok, statement, state}

      :error ->
        case Connection.prepare(state.connection, query.statement) do
          {:ok, statement} ->
            track(state.registry, state.worker, :statement, statement)
            {:ok, statement, %{state | prepared: Map.put(state.prepared, ref, statement)}}

          {:error, error} ->
            {:error, error, state}
        end
    end
  end

  defp error_result(%Error{code: code} = error, state) when code in @fatal_codes,
    do: {:disconnect, error, state}

  defp error_result(error, state), do: {:error, error, state}

  defp track(registry, worker, kind, resource) do
    native_resource = Map.fetch!(resource, :resource)
    :ets.insert(registry, {{worker, kind, native_resource}, {kind, resource}})
    :ok
  end

  defp untrack(state, kind, native_resource) do
    :ets.delete(state.registry, {state.worker, kind, native_resource})
    :ok
  end

  defp invalid(message) do
    %Error{code: :invalid_argument, operation: :pool, message: message}
  end
end
