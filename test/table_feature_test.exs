defmodule Tursox.TableFeatureTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.{Connection, Cursor, Database, Error, Native}

  setup %{tmp_dir: root} do
    baseline = Native.resource_snapshot()
    on_exit(fn -> assert baseline == Native.resource_snapshot() end)
    {:ok, root: root}
  end

  test "triggers apply and roll back atomically without a feature flag" do
    {database, connection} = open(:memory)

    :ok =
      Connection.execute_batch(connection, """
      CREATE TABLE accounts(id INTEGER PRIMARY KEY, balance INTEGER);
      CREATE TABLE audit(account_id INTEGER, old_balance INTEGER, new_balance INTEGER);
      INSERT INTO accounts VALUES (1, 10);
      CREATE TRIGGER account_update AFTER UPDATE OF balance ON accounts
      BEGIN
        INSERT INTO audit VALUES (old.id, old.balance, new.balance);
      END;
      """)

    :ok = Connection.execute(connection, "UPDATE accounts SET balance = 11 WHERE id = 1")
    assert rows(connection, "SELECT * FROM audit") == [[1, 10, 11]]

    :ok = Connection.begin(connection)
    :ok = Connection.execute(connection, "UPDATE accounts SET balance = 99 WHERE id = 1")
    :ok = Connection.rollback(connection)
    assert rows(connection, "SELECT balance FROM accounts") == [[11]]
    assert rows(connection, "SELECT * FROM audit") == [[1, 10, 11]]

    assert rows(connection, "SELECT type, name FROM sqlite_schema WHERE name = 'account_update'") ==
             [["trigger", "account_update"]]

    :ok = Connection.execute(connection, "DROP TRIGGER account_update")
    close(database, connection)
  end

  test "WITHOUT ROWID enforces key semantics and survives reopen", %{root: root} do
    path = tmp_path(root, "without-rowid.db")
    {database, connection} = open(path, features: [:without_rowid])

    :ok =
      Connection.execute(
        connection,
        "CREATE TABLE compact(code TEXT PRIMARY KEY, value INTEGER) WITHOUT ROWID"
      )

    :ok = Connection.execute(connection, "INSERT INTO compact VALUES ('b', 2), ('a', 1)")

    assert rows(connection, "SELECT code, value FROM compact ORDER BY code") == [
             ["a", 1],
             ["b", 2]
           ]

    assert {:error, %Error{}} = Connection.query(connection, "SELECT rowid FROM compact")

    assert {:error, %Error{code: :constraint}} =
             Connection.execute(connection, "INSERT INTO compact VALUES (NULL, 3)")

    close(database, connection)

    {reopened, connection} = open(path, features: [:without_rowid])
    assert rows(connection, "SELECT COUNT(*) FROM compact") == [[2]]
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
