defmodule Tursox.Cursor do
  @moduledoc """
  A bounded, incremental row cursor owned by one `Tursox.Statement`.

  `fetch/2` transfers at most the requested number of rows. Use `stream/2` for
  lazy enumeration or `all/3` only with an explicit total-row limit.
  """

  alias Tursox.{Column, Error, Native, Result, Statement, Telemetry}

  @max_fetch 1_000_000

  @enforce_keys [:resource, :statement, :columns]
  defstruct [:resource, :statement, :columns, owns_statement: false]

  @opaque t :: %__MODULE__{
            resource: reference(),
            statement: Statement.t(),
            columns: [Column.t()],
            owns_statement: boolean()
          }

  @doc "Fetches no more than `max_rows` ordered rows."
  @spec fetch(t(), pos_integer()) ::
          {:rows, [[term()]]} | {:done, [[term()]]} | :done | {:error, Error.t()}
  def fetch(%__MODULE__{} = cursor, max_rows)
      when is_integer(max_rows) and max_rows > 0 and max_rows <= @max_fetch do
    Telemetry.span(:cursor_fetch, %{max_rows: max_rows}, fn -> do_fetch(cursor, max_rows) end)
  end

  def fetch(%__MODULE__{}, _max_rows) do
    {:error,
     %Error{
       code: :invalid_argument,
       operation: :cursor_fetch,
       message: "max_rows must be between 1 and #{@max_fetch}"
     }}
  end

  defp do_fetch(%__MODULE__{resource: resource} = cursor, max_rows) do
    case Native.cursor_fetch(resource, max_rows) do
      {:ok, {false, rows}} -> {:rows, rows}
      {:ok, {true, []}} -> terminal(cursor, :done)
      {:ok, {true, rows}} -> terminal(cursor, {:done, rows})
      {:error, error} -> {:error, Error.from_native(error)}
    end
  end

  @doc "Fetches one row, returning `{:row, row}` or `:done`."
  @spec step(t()) :: {:row, [term()]} | :done | {:error, Error.t()}
  def step(%__MODULE__{} = cursor) do
    case fetch(cursor, 1) do
      {:rows, [row]} -> {:row, row}
      {:done, [row]} -> {:row, row}
      :done -> :done
      {:error, error} -> {:error, error}
    end
  end

  @doc "Returns ordered column metadata, preserving duplicate names."
  @spec columns(t()) :: [Column.t()]
  def columns(%__MODULE__{columns: columns}), do: columns

  @doc "Builds a lazy stream whose early halt closes the cursor."
  @spec stream(t(), pos_integer()) :: Enumerable.t()
  def stream(%__MODULE__{} = cursor, fetch_size \\ 500)
      when is_integer(fetch_size) and fetch_size > 0 and fetch_size <= @max_fetch do
    Stream.resource(
      fn -> cursor end,
      fn
        :done ->
          {:halt, :done}

        cursor ->
          case fetch(cursor, fetch_size) do
            {:rows, rows} -> {rows, cursor}
            {:done, rows} -> {rows, :done}
            :done -> {:halt, :done}
            {:error, error} -> raise error
          end
      end,
      fn
        :done -> :ok
        cursor -> close(cursor)
      end
    )
  end

  @doc "Materializes rows only up to an explicit total limit."
  @spec all(t(), non_neg_integer(), pos_integer()) :: {:ok, Result.t()} | {:error, Error.t()}
  def all(cursor, limit, fetch_size \\ 500)

  def all(%__MODULE__{} = cursor, limit, fetch_size)
      when is_integer(limit) and limit >= 0 and is_integer(fetch_size) and fetch_size > 0 and
             fetch_size <= @max_fetch do
    collect(cursor, limit, fetch_size, [], 0)
  end

  def all(%__MODULE__{}, _limit, _fetch_size) do
    {:error,
     %Error{
       code: :invalid_argument,
       operation: :cursor_all,
       message: "limit must be non-negative and fetch_size must be positive"
     }}
  end

  @doc "Logically closes the cursor and releases its statement lease."
  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource} = cursor) do
    :ok = Native.cursor_close(resource)
    release_owned_statement(cursor)
    :ok
  end

  defp terminal(cursor, result) do
    release_owned_statement(cursor)
    result
  end

  defp release_owned_statement(%__MODULE__{owns_statement: true, statement: statement}),
    do: Statement.close(statement)

  defp release_owned_statement(_cursor), do: :ok

  defp collect(cursor, limit, fetch_size, chunks, count) do
    request = min(fetch_size, max(limit - count + 1, 1))

    case fetch(cursor, request) do
      {:rows, rows} -> append_or_continue(cursor, rows, false, limit, fetch_size, chunks, count)
      {:done, rows} -> append_or_continue(cursor, rows, true, limit, fetch_size, chunks, count)
      :done -> {:ok, result(cursor, chunks, count)}
      {:error, error} -> {:error, error}
    end
  end

  defp append_or_continue(cursor, rows, done, limit, fetch_size, chunks, count) do
    new_count = count + length(rows)

    if new_count > limit do
      close(cursor)

      {:error,
       %Error{
         code: :invalid_argument,
         operation: :cursor_all,
         message: "row limit exceeded"
       }}
    else
      chunks = [rows | chunks]

      if done,
        do: {:ok, result(cursor, chunks, new_count)},
        else: collect(cursor, limit, fetch_size, chunks, new_count)
    end
  end

  defp result(cursor, chunks, count) do
    %Result{
      columns: cursor.columns,
      rows: chunks |> Enum.reverse() |> Enum.flat_map(& &1),
      num_rows: count
    }
  end
end

defimpl Enumerable, for: Tursox.Cursor do
  def reduce(cursor, acc, fun), do: Enumerable.reduce(Tursox.Cursor.stream(cursor), acc, fun)
  def count(_cursor), do: {:error, __MODULE__}
  def member?(_cursor, _value), do: {:error, __MODULE__}
  def slice(_cursor), do: {:error, __MODULE__}
end

defimpl Inspect, for: Tursox.Cursor do
  import Inspect.Algebra

  def inspect(cursor, opts) do
    concat(["#Tursox.Cursor<columns: ", to_doc(cursor.columns, opts), ">"])
  end
end
