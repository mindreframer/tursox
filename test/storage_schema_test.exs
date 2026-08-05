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

  test "vacuum and autovacuum remain explicit opt-ins", %{root: root} do
    path = tmp_path(root, "compaction.db")
    {database, connection} = open(path)

    assert {:error, %Error{code: :misuse}} = Connection.execute(connection, "VACUUM")

    assert {:error, %Error{code: :misuse}} =
             Connection.pragma_update(connection, :auto_vacuum, :full)

    close(database, connection)

    {autovacuum_db, autovacuum} = open(path, features: [:autovacuum])
    assert {:ok, []} = Connection.pragma_update(autovacuum, :auto_vacuum, :full)
    close(autovacuum_db, autovacuum)

    {:ok, vacuum_db} = Database.open(path, unsafe_features: [:vacuum])
    assert Database.metadata(vacuum_db).unsafe_features == [:vacuum]
    Database.close(vacuum_db)
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
