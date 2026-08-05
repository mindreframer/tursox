defmodule Tursox.StatementCursorTest do
  use ExUnit.Case, async: false

  alias Tursox.{Connection, Cursor, Database, Error, Native, Result, Statement}

  setup do
    baseline = Native.resource_snapshot()
    {:ok, database} = Database.open(:memory)
    {:ok, connection} = Database.connect(database)

    on_exit(fn ->
      Connection.close(connection)
      Database.close(database)
      assert baseline == Native.resource_snapshot()
    end)

    {:ok, database: database, connection: connection, baseline: baseline}
  end

  test "all SQLite storage classes and parameter boundaries round-trip", %{connection: connection} do
    :ok =
      Connection.execute(
        connection,
        "CREATE TABLE values_test (n, i INTEGER, r REAL, t TEXT, b BLOB, yes INTEGER, no INTEGER)"
      )

    {:ok, insert} =
      Connection.prepare(
        connection,
        "INSERT INTO values_test VALUES (?, ?, ?, ?, ?, ?, ?)"
      )

    blob = <<0, 255, 1, 128>>

    assert {:ok, %Result{num_rows: 1, last_insert_rowid: rowid}} =
             Statement.execute(insert, [
               nil,
               -9_223_372_036_854_775_808,
               1.25,
               "héllo",
               {:blob, blob},
               true,
               false
             ])

    assert rowid > 0

    assert {:ok, %Result{num_rows: 1}} =
             Statement.execute(insert, [
               nil,
               9_223_372_036_854_775_807,
               2.5,
               "",
               {:blob, <<>>},
               false,
               true
             ])

    :ok = Statement.close(insert)

    {:ok, cursor} =
      Connection.query(
        connection,
        "SELECT n, i, r, t, b, yes, no FROM values_test ORDER BY rowid"
      )

    assert {:done,
            [
              [nil, -9_223_372_036_854_775_808, 1.25, "héllo", {:blob, ^blob}, 1, 0],
              [nil, 9_223_372_036_854_775_807, 2.5, "", {:blob, <<>>}, 0, 1]
            ]} = Cursor.fetch(cursor, 10)

    assert :done = Cursor.fetch(cursor, 10)

    assert {:error, %Error{code: :invalid_argument}} =
             Connection.execute(connection, "SELECT ?", [9_223_372_036_854_775_808])

    assert {:error, %Error{code: :invalid_argument}} =
             Connection.execute(connection, "SELECT ?", [<<255>>])
  end

  test "positional and prefixed named parameters bind strictly", %{connection: connection} do
    :ok = Connection.execute(connection, "CREATE TABLE named_test (a INTEGER, b TEXT)")

    assert :ok =
             Connection.execute(
               connection,
               "INSERT INTO named_test VALUES (:amount, $label)",
               amount: 3,
               "$label": "three"
             )

    {:ok, cursor} =
      Connection.query(
        connection,
        "SELECT a, b FROM named_test WHERE a = @amount AND b = :label",
        [{"@amount", 3}, {:label, "three"}]
      )

    assert {:done, [[3, "three"]]} = Cursor.fetch(cursor, 5)

    assert {:error, %Error{code: :invalid_argument}} =
             Connection.execute(connection, "SELECT :a", [{:a, 1}, {":a", 2}])

    assert {:error, %Error{code: code}} =
             Connection.execute(connection, "SELECT ?", [])

    assert code in [:misuse, :invalid_argument]
  end

  test "prepared statements reset and reject concurrent cursor use", %{connection: connection} do
    {:ok, statement} = Connection.prepare(connection, "SELECT ? AS value")
    {:ok, cursor} = Statement.query(statement, [1])

    assert {:error, %Error{code: :misuse}} = Statement.query(statement, [2])
    assert {:error, %Error{code: :misuse}} = Statement.execute(statement, [2])
    assert {:error, %Error{code: :misuse}} = Statement.reset(statement)

    assert {:done, [[1]]} = Cursor.fetch(cursor, 10)
    assert :ok = Statement.reset(statement)

    {:ok, cursor} = Statement.query(statement, [2])
    assert {:done, [[2]]} = Cursor.fetch(cursor, 10)
    :ok = Statement.close(statement)
  end

  test "duplicate columns and order are preserved with explicit map collision policy", %{
    connection: connection
  } do
    {:ok, cursor} = Connection.query(connection, "SELECT 1 AS same, 2 AS same, 3 AS last")
    assert Enum.map(Cursor.columns(cursor), & &1.name) == ["same", "same", "last"]
    assert {:ok, result} = Cursor.all(cursor, 10, 2)
    assert result.rows == [[1, 2, 3]]

    assert {:error, %Error{code: :conversion}} = Result.to_maps(result)
    assert {:ok, [%{"same" => 1, "last" => 3}]} = Result.to_maps(result, :first)
    assert {:ok, [%{"same" => 2, "last" => 3}]} = Result.to_maps(result, :last)
  end

  test "large results are fetched only in requested chunks", %{connection: connection} do
    :ok = Connection.execute(connection, "CREATE TABLE chunks (value INTEGER)")

    sql = Enum.map_join(1..257, ";", &"INSERT INTO chunks VALUES (#{&1})")
    assert :ok = Connection.execute_batch(connection, sql)

    {:ok, cursor} = Connection.query(connection, "SELECT value FROM chunks ORDER BY value")
    rows = fetch_chunks(cursor, 17, [])

    assert length(rows) == 257
    assert hd(rows) == [1]
    assert List.last(rows) == [257]
  end

  test "early Enumerable halt closes the cursor and releases the lease", %{
    connection: connection,
    baseline: baseline
  } do
    seed_rows(connection, "early_rows", 100)

    {:ok, statement} =
      Connection.prepare(connection, "SELECT value FROM early_rows ORDER BY value")

    {:ok, cursor} = Statement.query(statement)
    assert Enum.take(Cursor.stream(cursor, 8), 3) == [[1], [2], [3]]

    snapshot = Native.resource_snapshot()
    assert snapshot.cursors == baseline.cursors
    assert snapshot.statements == baseline.statements + 1

    {:ok, cursor} = Statement.query(statement)
    assert {:rows, rows} = Cursor.fetch(cursor, 5)
    assert length(rows) == 5
    :ok = Cursor.close(cursor)
    :ok = Statement.close(statement)
  end

  test "limited all refuses implicit unbounded materialization", %{connection: connection} do
    seed_rows(connection, "limited_rows", 20)
    {:ok, cursor} = Connection.query(connection, "SELECT value FROM limited_rows ORDER BY value")

    assert {:error, %Error{operation: :cursor_all, message: "row limit exceeded"}} =
             Cursor.all(cursor, 5, 3)
  end

  test "execute batch errors are redacted and close ordering is safe", %{connection: connection} do
    sql = "CREATE TABLE batch_test (id INTEGER); INSERT INTO missing VALUES (1)"
    assert {:error, %Error{} = error} = Connection.execute_batch(connection, sql)
    refute error.message =~ sql

    {:ok, statement} = Connection.prepare(connection, "SELECT 1")
    {:ok, cursor} = Statement.query(statement)
    :ok = Statement.close(statement)
    assert {:error, %Error{code: :closed}} = Cursor.fetch(cursor, 1)
    :ok = Cursor.close(cursor)
  end

  defp seed_rows(connection, table, count) do
    :ok = Connection.execute(connection, "CREATE TABLE #{table} (value INTEGER)")
    sql = Enum.map_join(1..count, ";", &"INSERT INTO #{table} VALUES (#{&1})")
    :ok = Connection.execute_batch(connection, sql)
  end

  defp fetch_chunks(cursor, size, acc) do
    case Cursor.fetch(cursor, size) do
      {:rows, rows} ->
        assert length(rows) <= size
        fetch_chunks(cursor, size, [rows | acc])

      {:done, rows} ->
        assert length(rows) <= size
        acc |> Enum.reverse() |> Enum.flat_map(& &1) |> Kernel.++(rows)

      :done ->
        acc |> Enum.reverse() |> Enum.flat_map(& &1)
    end
  end
end
