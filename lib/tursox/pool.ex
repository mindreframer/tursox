defmodule Tursox.Pool do
  @moduledoc """
  Optional `DBConnection` pool whose workers derive connections from one database.

  Starting a pool with a path owns exactly one database resource. Passing an
  existing `Tursox.Database` leaves it caller-owned unless `own_database: true`.
  """

  alias Tursox.{Error, Pool.Owner, Query, Result}

  @custom_options [:busy_timeout, :database, :database_options, :own_database]

  @doc "Starts a shared-handle DBConnection pool."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    with :ok <- validate_options(opts) do
      Owner.start_link(opts)
    end
  end

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, Keyword.get(opts, :name, __MODULE__)),
      start: {__MODULE__, :start_link, [Keyword.delete(opts, :id)]},
      type: :worker
    }
  end

  @doc "Stops the pool, drains workers, and closes an owned database."
  @spec stop(GenServer.server(), timeout()) :: :ok
  def stop(pool, timeout \\ 15_000), do: GenServer.stop(pool, :normal, timeout)

  @doc "Returns the underlying DBConnection pool PID."
  @spec pool(GenServer.server() | DBConnection.t()) :: pid() | DBConnection.t()
  def pool(%DBConnection{} = connection), do: connection
  def pool(owner), do: Owner.pool(owner)

  @doc "Returns redacted ownership and database metadata."
  def metadata(owner), do: Owner.metadata(owner)

  @doc "Executes a write/DDL statement through DBConnection."
  @spec execute(GenServer.server() | DBConnection.t(), String.t(), term(), keyword()) ::
          {:ok, Result.t()} | {:error, Exception.t()}
  def execute(pool, sql, params \\ [], opts \\ []) do
    query = Query.new(sql, :execute, persistent: false)

    case DBConnection.prepare_execute(resolve(pool), query, params, opts) do
      {:ok, _query, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Executes a bounded materialized query through DBConnection."
  @spec query(GenServer.server() | DBConnection.t(), String.t(), term(), keyword()) ::
          {:ok, Result.t()} | {:error, Exception.t()}
  def query(pool, sql, params \\ [], opts \\ []) do
    query = Query.new(sql, :query, persistent: false)

    case DBConnection.prepare_execute(resolve(pool), query, params, opts) do
      {:ok, _query, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Prepares a reusable query through DBConnection."
  @spec prepare(GenServer.server() | DBConnection.t(), String.t(), :query | :execute, keyword()) ::
          {:ok, Query.t()} | {:error, Exception.t()}
  def prepare(pool, sql, command \\ :query, opts \\ []) when command in [:query, :execute] do
    DBConnection.prepare(resolve(pool), Query.new(sql, command), opts)
  end

  @doc "Executes a query returned by `prepare/4`."
  def execute_prepared(pool, %Query{} = query, params \\ [], opts \\ []) do
    case DBConnection.execute(resolve(pool), query, params, opts) do
      {:ok, query, result} -> {:ok, query, result}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Closes a prepared query on one checked-out worker."
  def close(pool, %Query{} = query, opts \\ []),
    do: DBConnection.close(resolve(pool), query, opts)

  @doc "Returns a checkout-bound bounded DBConnection stream."
  @spec stream(GenServer.server() | DBConnection.t(), String.t(), term(), keyword()) ::
          Enumerable.t()
  def stream(pool, sql, params \\ [], opts \\ []) do
    %Tursox.Pool.Stream{pool: pool, query: Query.new(sql, :query), params: params, opts: opts}
  end

  @doc "Runs a DBConnection transaction with the requested Tursox mode."
  def transaction(pool, fun, opts \\ []) when is_function(fun, 1) do
    DBConnection.transaction(resolve(pool), fun, opts)
  end

  defp resolve(%DBConnection{} = connection), do: connection
  defp resolve(owner), do: Owner.pool(owner)

  defp validate_options(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, invalid("pool options must be a keyword list")}

      (unknown =
         Keyword.keys(opts) --
           (@custom_options ++ DBConnection.available_start_options() ++ [:id])) != [] ->
        {:error, invalid("unknown pool options: #{inspect(unknown)}")}

      not (is_integer(Keyword.get(opts, :pool_size, 1)) and Keyword.get(opts, :pool_size, 1) > 0) ->
        {:error, invalid("pool_size must be positive")}

      true ->
        :ok
    end
  end

  defp invalid(message),
    do: %Error{code: :invalid_argument, operation: :pool_start, message: message}
end
