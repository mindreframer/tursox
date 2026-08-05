defmodule Tursox.Connection do
  @moduledoc """
  A sequential connection derived from one `Tursox.Database` resource.

  Closing the parent database safely invalidates this resource. Mutable native
  operations are serialized per connection; independent connections do not use
  a global lock.
  """

  alias Tursox.{Database, Error, Native}

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
