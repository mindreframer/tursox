defmodule Tursox.Connection do
  @moduledoc """
  A sequential connection derived from one `Tursox.Database` resource.

  Closing the parent database safely invalidates this resource. Mutable native
  operations are serialized per connection; independent connections do not use
  a global lock.
  """

  alias Tursox.{Column, Database, Error, Native, Parameters, Result, Statement, Transaction}

  @enforce_keys [:resource, :database, :busy_timeout]
  defstruct [:resource, :database, :busy_timeout]

  @opaque t :: %__MODULE__{
            resource: reference(),
            database: Database.t(),
            busy_timeout: non_neg_integer()
          }

  @pragma_atoms [
    :delete,
    :truncate,
    :persist,
    :memory,
    :wal,
    :mvcc,
    :off,
    :passive,
    :full,
    :restart
  ]

  @doc "Logically closes a connection. It is safe to call repeatedly."
  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource}), do: Native.connection_close(resource)

  @doc "Executes one bound SQL statement and discards execution metadata."
  @spec execute(t(), String.t(), term()) :: :ok | {:error, Error.t()}
  def execute(%__MODULE__{} = connection, sql, params \\ []) do
    case execute_result(connection, sql, params) do
      {:ok, %Result{}} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc "Executes one bound SQL statement and returns affected-row metadata."
  @spec execute_result(t(), String.t(), term()) :: {:ok, Result.t()} | {:error, Error.t()}
  def execute_result(%__MODULE__{resource: resource}, sql, params \\ []) do
    with :ok <- validate_sql(sql, :connection_execute),
         {:ok, {named, names, values}} <- Parameters.normalize(params, :connection_execute),
         {:ok, {changed, rowid}} <-
           native(Native.connection_execute(resource, sql, named, names, values)) do
      {:ok, %Result{num_rows: changed, last_insert_rowid: rowid}}
    end
  end

  @doc "Executes all statements in a SQL batch without bound parameters."
  @spec execute_batch(t(), String.t()) :: :ok | {:error, Error.t()}
  def execute_batch(%__MODULE__{resource: resource}, sql) do
    with :ok <- validate_sql(sql, :connection_execute_batch) do
      case Native.connection_execute_batch(resource, sql) do
        {:ok, :ok} -> :ok
        {:error, error} -> {:error, Error.from_native(error)}
      end
    end
  end

  @doc "Prepares a real native statement owned by this connection."
  @spec prepare(t(), String.t()) :: {:ok, Statement.t()} | {:error, Error.t()}
  def prepare(%__MODULE__{resource: resource} = connection, sql) do
    with :ok <- validate_sql(sql, :connection_prepare),
         {:ok, statement} <- native(Native.connection_prepare(resource, sql)),
         {:ok, columns} <- native(Native.statement_columns(statement)) do
      {:ok,
       %Statement{
         resource: statement,
         connection: connection,
         columns:
           Enum.map(columns, fn {name, declaration_type} ->
             %Column{name: name, declaration_type: declaration_type}
           end)
       }}
    end
  end

  @doc "Prepares and starts a bounded native cursor convenience query."
  @spec query(t(), String.t(), term()) :: {:ok, Tursox.Cursor.t()} | {:error, Error.t()}
  def query(%__MODULE__{} = connection, sql, params \\ []) do
    with {:ok, statement} <- prepare(connection, sql) do
      case Statement.query(statement, params) do
        {:ok, cursor} ->
          {:ok, %{cursor | owns_statement: true}}

        {:error, error} ->
          Statement.close(statement)
          {:error, error}
      end
    end
  end

  @doc "Returns the row ID from the most recent successful insert."
  @spec last_insert_rowid(t()) :: {:ok, integer()} | {:error, Error.t()}
  def last_insert_rowid(%__MODULE__{resource: resource}) do
    native(Native.connection_last_insert_rowid(resource))
  end

  @doc "Begins a deferred, immediate, exclusive, or MVCC concurrent transaction."
  def begin(connection, opts \\ []), do: Transaction.begin(connection, opts)

  @doc "Commits the active transaction."
  def commit(connection), do: Transaction.commit(connection)

  @doc "Rolls back the active transaction."
  def rollback(connection), do: Transaction.rollback(connection)

  @doc "Runs a rollback-safe transaction callback."
  def transaction(connection, fun, opts \\ []), do: Transaction.transaction(connection, fun, opts)

  @doc "Retries a complete transaction callback after classified conflicts."
  def retry_transaction(connection, fun, opts \\ []),
    do: Transaction.retry_transaction(connection, fun, opts)

  @doc "Runs a tested WAL/MVCC checkpoint pragma."
  def checkpoint(connection, mode \\ :passive), do: Transaction.checkpoint(connection, mode)

  @doc "Sets and verifies the experimental MVCC checkpoint threshold."
  def set_mvcc_checkpoint_threshold(connection, threshold),
    do: Transaction.set_mvcc_checkpoint_threshold(connection, threshold)

  @doc "Returns whether this connection is currently in autocommit mode."
  @spec autocommit?(t()) :: {:ok, boolean()} | {:error, Error.t()}
  def autocommit?(%__MODULE__{resource: resource}) do
    native(Native.connection_status(resource))
  end

  @doc "Returns `:idle` in autocommit mode and `:transaction` otherwise."
  @spec status(t()) :: {:ok, :idle | :transaction} | {:error, Error.t()}
  def status(%__MODULE__{} = connection) do
    case autocommit?(connection) do
      {:ok, true} -> {:ok, :idle}
      {:ok, false} -> {:ok, :transaction}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Flushes dirty connection pages to the journal."
  @spec cache_flush(t()) :: :ok | {:error, Error.t()}
  def cache_flush(%__MODULE__{resource: resource}) do
    case Native.connection_cache_flush(resource) do
      {:ok, :ok} -> :ok
      {:error, error} -> {:error, Error.from_native(error)}
    end
  end

  @doc "Runs a validated pragma query and returns ordered row lists."
  @spec pragma_query(t(), atom() | String.t()) :: {:ok, [[term()]]} | {:error, Error.t()}
  def pragma_query(%__MODULE__{resource: resource}, name) do
    with {:ok, name} <- pragma_name(name) do
      native(Native.connection_pragma_query(resource, name))
    end
  end

  @doc "Updates a validated pragma and returns any ordered result rows."
  @spec pragma_update(t(), atom() | String.t(), term()) ::
          {:ok, [[term()]]} | {:error, Error.t()}
  def pragma_update(%__MODULE__{resource: resource}, name, value) do
    with {:ok, name} <- pragma_name(name),
         {:ok, value} <- pragma_value(value) do
      native(Native.connection_pragma_update(resource, name, value))
    end
  end

  defp pragma_name(name) when is_atom(name), do: pragma_name(Atom.to_string(name))

  defp pragma_name(name) when is_binary(name) do
    if Regex.match?(~r/^[A-Za-z][A-Za-z0-9_]*$/, name) do
      {:ok, name}
    else
      invalid("pragma name must be a simple identifier")
    end
  end

  defp pragma_name(_name), do: invalid("pragma name must be an atom or string")

  defp pragma_value(value) when is_integer(value), do: {:ok, Integer.to_string(value)}
  defp pragma_value(true), do: {:ok, "1"}
  defp pragma_value(false), do: {:ok, "0"}
  defp pragma_value(value) when value in @pragma_atoms, do: {:ok, Atom.to_string(value)}

  defp pragma_value(value) when is_binary(value) do
    {:ok, "'#{String.replace(value, "'", "''")}'"}
  end

  defp pragma_value(_value),
    do: invalid("pragma value must be an integer, boolean, supported atom, or string")

  defp validate_sql(sql, _operation) when is_binary(sql) and byte_size(sql) > 0, do: :ok

  defp validate_sql(_sql, operation) do
    {:error,
     %Error{
       code: :invalid_argument,
       operation: operation,
       message: "SQL must be a non-empty string"
     }}
  end

  defp native({:ok, value}), do: {:ok, value}
  defp native({:error, error}), do: {:error, Error.from_native(error)}

  defp invalid(message) do
    {:error, %Error{code: :invalid_argument, operation: :connection_pragma, message: message}}
  end
end

defimpl Inspect, for: Tursox.Connection do
  import Inspect.Algebra

  def inspect(connection, opts) do
    concat([
      "#Tursox.Connection<database: ",
      to_doc(connection.database.path, opts),
      ", busy_timeout: ",
      to_doc(connection.busy_timeout, opts),
      ">"
    ])
  end
end
