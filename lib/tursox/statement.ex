defmodule Tursox.Statement do
  @moduledoc """
  A real prepared statement owned by one `Tursox.Connection`.

  One cursor may be active at a time. Reset, execution, or a second query while
  that cursor is active returns `:misuse` rather than resetting shared engine
  state underneath it.
  """

  alias Tursox.{Column, Connection, Cursor, Error, Native, Parameters, Result}

  @enforce_keys [:resource, :connection, :columns]
  defstruct [:resource, :connection, :columns]

  @opaque t :: %__MODULE__{
            resource: reference(),
            connection: Connection.t(),
            columns: [Column.t()]
          }

  @doc "Executes this prepared statement and returns affected-row metadata."
  @spec execute(t(), term()) :: {:ok, Result.t()} | {:error, Error.t()}
  def execute(%__MODULE__{resource: resource}, params \\ []) do
    with {:ok, {named, names, values}} <- Parameters.normalize(params, :statement_execute),
         {:ok, {changed, rowid}} <-
           native(Native.statement_execute(resource, named, names, values)) do
      {:ok, %Result{num_rows: changed, last_insert_rowid: rowid}}
    end
  end

  @doc "Starts an incremental native row cursor."
  @spec query(t(), term()) :: {:ok, Cursor.t()} | {:error, Error.t()}
  def query(%__MODULE__{resource: resource} = statement, params \\ []) do
    with {:ok, {named, names, values}} <- Parameters.normalize(params, :statement_query),
         {:ok, cursor} <- native(Native.statement_query(resource, named, names, values)) do
      {:ok, %Cursor{resource: cursor, statement: statement, columns: statement.columns}}
    end
  end

  @doc "Resets a completed statement for explicit reuse."
  @spec reset(t()) :: :ok | {:error, Error.t()}
  def reset(%__MODULE__{resource: resource}) do
    case Native.statement_reset(resource) do
      {:ok, :ok} -> :ok
      {:error, error} -> {:error, Error.from_native(error)}
    end
  end

  @doc "Returns ordered column metadata, including duplicate names."
  @spec columns(t()) :: [Column.t()]
  def columns(%__MODULE__{columns: columns}), do: columns

  @doc "Logically closes a statement. It is safe to call repeatedly."
  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource}), do: Native.statement_close(resource)

  defp native({:ok, value}), do: {:ok, value}
  defp native({:error, error}), do: {:error, Error.from_native(error)}
end

defimpl Inspect, for: Tursox.Statement do
  import Inspect.Algebra

  def inspect(statement, opts) do
    concat(["#Tursox.Statement<columns: ", to_doc(statement.columns, opts), ">"])
  end
end
