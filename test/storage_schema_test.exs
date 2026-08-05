defmodule Tursox.StorageSchemaTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.{Connection, Cursor, Database, Error, Native}

  setup %{tmp_dir: root} do
    baseline = Native.resource_snapshot()
    on_exit(fn -> assert baseline == Native.resource_snapshot() end)
    {:ok, root: root}
  end

  test "attached schemas remain isolated, persist independently, and detach cleanly", %{
    root: root
  } do
    main_path = tmp_path(root, "main.db")
    aux_path = tmp_path(root, "auxiliary.db")
    {database, connection} = open(main_path, features: [:attach])
    :ok = Connection.execute(connection, "CREATE TABLE same_name(value TEXT)")
    :ok = Connection.execute(connection, "INSERT INTO same_name VALUES ('main')")
    :ok = Connection.execute(connection, "ATTACH DATABASE '#{aux_path}' AS aux")
    :ok = Connection.execute(connection, "CREATE TABLE aux.same_name(value TEXT)")
    :ok = Connection.execute(connection, "INSERT INTO aux.same_name VALUES ('aux')")

    assert rows(connection, "SELECT value FROM main.same_name") == [["main"]]
    assert rows(connection, "SELECT value FROM aux.same_name") == [["aux"]]
    assert length(rows(connection, "PRAGMA database_list")) == 2

    :ok = Connection.execute(connection, "DETACH DATABASE aux")
    assert {:error, %Error{}} = Connection.query(connection, "SELECT * FROM aux.same_name")
    close(database, connection)

    {aux_db, aux} = open(aux_path)
    assert rows(aux, "SELECT value FROM same_name") == [["aux"]]
    close(aux_db, aux)
  end

  test "vacuum works on initialized files; autovacuum switch is absent", %{root: root} do
    path = tmp_path(root, "vacuum.db")
    {database, connection} = open(path, features: [:vacuum])
    assert {:ok, [[]]} = Connection.pragma_query(connection, :auto_vacuum)

    assert {:error, %Error{code: :misuse}} =
             Connection.pragma_update(connection, :auto_vacuum, 1)

    :ok =
      Connection.execute(connection, "CREATE TABLE payload(id INTEGER PRIMARY KEY, body BLOB)")

    blob = {:blob, :binary.copy(<<7>>, 4_096)}

    for id <- 1..40 do
      :ok = Connection.execute(connection, "INSERT INTO payload VALUES (?, ?)", [id, blob])
    end

    :ok = Connection.execute(connection, "DELETE FROM payload WHERE id <= 30")
    {:ok, [[pages_before]]} = Connection.pragma_query(connection, :page_count)
    :ok = Connection.execute(connection, "VACUUM")
    {:ok, [[pages_after]]} = Connection.pragma_query(connection, :page_count)
    assert pages_after <= pages_before
    assert rows(connection, "SELECT COUNT(*) FROM payload") == [[10]]
    assert {:ok, [["ok"]]} = Connection.pragma_query(connection, :integrity_check)
    close(database, connection)

    {reopened, connection} = open(path, features: [:vacuum])
    assert rows(connection, "SELECT COUNT(*) FROM payload") == [[10]]
    close(reopened, connection)
  end

  defp open(path, opts \\ []) do
    {:ok, database} = Database.open(path, opts)
    {:ok, connection} = Database.connect(database)
    {database, connection}
  end

  defp rows(connection, sql) do
    {:ok, cursor} = Connection.query(connection, sql)
    {:ok, result} = Cursor.all(cursor, 10_000, 64)
    result.rows
  end

  defp close(database, connection) do
    Connection.close(connection)
    Database.close(database)
  end
end
