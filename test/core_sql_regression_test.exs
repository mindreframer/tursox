defmodule Tursox.CoreSqlRegressionTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.{Connection, Cursor, Database, Error, Manager, Native, Pool, Result, Statement}

  setup do
    baseline = Native.resource_snapshot()
    on_exit(fn -> assert baseline == Native.resource_snapshot() end)
    :ok
  end

  for kind <- [:memory, :file] do
    @kind kind
    test "DDL, CRUD, expressions, joins, grouping, and compounds on #{@kind}", %{tmp_dir: root} do
      {database, connection} = open(unquote(kind), root)

      assert :ok =
               Connection.execute_batch(connection, """
               CREATE TABLE accounts (
                 id INTEGER PRIMARY KEY,
                 name TEXT NOT NULL UNIQUE,
                 balance REAL DEFAULT 0,
                 payload BLOB,
                 active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1))
               );
               CREATE INDEX accounts_balance_idx ON accounts(balance);
               ALTER TABLE accounts ADD COLUMN note TEXT DEFAULT 'new';
               CREATE TABLE transfers (
                 id INTEGER PRIMARY KEY,
                 account_id INTEGER REFERENCES accounts(id),
                 amount INTEGER NOT NULL
               );
               """)

      blob = <<0, 1, 127, 128, 255>>

      assert {:ok, %Result{num_rows: 1}} =
               Connection.execute_result(
                 connection,
                 "INSERT INTO accounts(id, name, balance, payload) VALUES (?, ?, ?, ?)",
                 [1, "Åda 数据库", 10.5, {:blob, blob}]
               )

      assert :ok =
               Connection.execute(
                 connection,
                 "INSERT INTO accounts(id, name, balance, active, note) VALUES (:id, :name, :balance, :active, :note)",
                 %{id: 2, name: "Grace", balance: 7, active: false, note: nil}
               )

      assert :ok =
               Connection.execute(
                 connection,
                 "INSERT INTO accounts(id, name, balance) VALUES (2, 'Grace', 9) " <>
                   "ON CONFLICT(id) DO UPDATE SET balance = excluded.balance"
               )

      assert {:ok, cursor} =
               Connection.query(
                 connection,
                 """
                 SELECT id, name, balance, typeof(balance), payload, active, note,
                        CASE WHEN balance >= 9 THEN 'high' ELSE 'low' END
                 FROM accounts ORDER BY balance DESC, id
                 """
               )

      assert {:done,
              [
                [1, "Åda 数据库", 10.5, "real", {:blob, ^blob}, 1, "new", "high"],
                [2, "Grace", 9.0, "real", nil, 0, nil, "high"]
              ]} = Cursor.fetch(cursor, 10)

      assert :ok =
               Connection.execute_batch(
                 connection,
                 "INSERT INTO transfers VALUES (1, 1, 4); INSERT INTO transfers VALUES (2, 1, 6); INSERT INTO transfers VALUES (3, 2, 3)"
               )

      assert rows(connection, """
             SELECT a.name, COUNT(t.id), SUM(t.amount)
             FROM accounts a LEFT JOIN transfers t ON t.account_id = a.id
             GROUP BY a.id, a.name HAVING SUM(t.amount) >= 3
             ORDER BY SUM(t.amount) DESC, a.id
             """) == [["Åda 数据库", 2, 10], ["Grace", 1, 3]]

      assert rows(connection, """
             SELECT id FROM accounts WHERE id IN (SELECT account_id FROM transfers WHERE amount > 5)
             UNION SELECT account_id FROM transfers WHERE amount = 3 ORDER BY 1
             """) == [[1], [2]]

      assert rows(connection, "SELECT 2 + 3, 7 / 2, coalesce(NULL, 'x'), NULL IS NULL") ==
               [[5, 3, "x", 1]]

      assert rows(
               connection,
               "UPDATE accounts SET balance = balance + 1 WHERE id = 2 RETURNING id, balance"
             ) == [[2, 10.0]]

      assert rows(connection, "DELETE FROM transfers WHERE id = 3 RETURNING id") == [[3]]

      close(database, connection)
    end
  end

  test "constraints and failed batches leave deliberate transaction boundaries", %{tmp_dir: root} do
    {database, connection} = open(:file, root)
    :ok = Connection.execute(connection, "PRAGMA foreign_keys = ON")

    :ok =
      Connection.execute_batch(connection, """
      CREATE TABLE parents(id INTEGER PRIMARY KEY);
      CREATE TABLE children(
        id INTEGER PRIMARY KEY,
        parent_id INTEGER NOT NULL REFERENCES parents(id),
        token TEXT NOT NULL UNIQUE,
        amount INTEGER CHECK(amount > 0)
      );
      INSERT INTO parents VALUES (1);
      """)

    for {sql, params} <- [
          {"INSERT INTO children VALUES (1, 99, 'a', 1)", []},
          {"INSERT INTO children VALUES (1, 1, NULL, 1)", []},
          {"INSERT INTO children VALUES (1, 1, 'a', 0)", []}
        ] do
      assert {:error, %Error{code: :constraint}} = Connection.execute(connection, sql, params)
      assert rows(connection, "SELECT COUNT(*) FROM children") == [[0]]
    end

    assert {:error, %Error{}} =
             Connection.transaction(connection, fn ->
               :ok = Connection.execute(connection, "INSERT INTO children VALUES (1, 1, 'a', 1)")
               Connection.execute(connection, "INSERT INTO children VALUES (2, 1, 'a', 2)")
             end)

    assert rows(connection, "SELECT COUNT(*) FROM children") == [[0]]

    assert {:ok, :committed} =
             Connection.transaction(connection, fn ->
               :ok = Connection.execute(connection, "INSERT INTO children VALUES (1, 1, 'a', 1)")
               :committed
             end)

    assert rows(connection, "SELECT id, token FROM children") == [[1, "a"]]
    close(database, connection)
  end

  test "prepared statements are reusable and cursors stay bounded" do
    {:ok, database} = Database.open(:memory)
    {:ok, connection} = Database.connect(database)
    :ok = Connection.execute(connection, "CREATE TABLE prepared(id INTEGER PRIMARY KEY, value)")
    {:ok, insert} = Connection.prepare(connection, "INSERT INTO prepared VALUES (?, ?)")

    for {id, value} <- [{1, nil}, {2, -1}, {3, 1.5}, {4, "text"}, {5, {:blob, <<1, 2>>}}] do
      assert {:ok, %Result{num_rows: 1}} = Statement.execute(insert, [id, value])
      assert :ok = Statement.reset(insert)
    end

    :ok = Statement.close(insert)
    {:ok, cursor} = Connection.query(connection, "SELECT id, value FROM prepared ORDER BY id")
    assert {:rows, [[1, nil], [2, -1]]} = Cursor.fetch(cursor, 2)
    assert {:rows, [[3, 1.5], [4, "text"]]} = Cursor.fetch(cursor, 2)
    assert {:done, [[5, {:blob, <<1, 2>>}]]} = Cursor.fetch(cursor, 2)
    close(database, connection)
  end

  test "commit visibility, rollback, and reopen durability", %{tmp_dir: root} do
    path = tmp_path(root)
    {:ok, database} = Database.open(path)
    {:ok, writer} = Database.connect(database)
    {:ok, reader} = Database.connect(database)

    :ok =
      Connection.execute(writer, "CREATE TABLE visibility(id INTEGER PRIMARY KEY, value TEXT)")

    :ok = Connection.begin(writer, mode: :immediate)
    :ok = Connection.execute(writer, "INSERT INTO visibility VALUES (1, 'committed')")
    assert rows(reader, "SELECT COUNT(*) FROM visibility") == [[0]]
    :ok = Connection.commit(writer)
    assert rows(reader, "SELECT id, value FROM visibility") == [[1, "committed"]]

    :ok = Connection.begin(writer)
    :ok = Connection.execute(writer, "INSERT INTO visibility VALUES (2, 'rolled back')")
    :ok = Connection.rollback(writer)
    close(database, writer, [reader])

    {:ok, reopened} = Database.open(path)
    {:ok, connection} = Database.connect(reopened)
    assert rows(connection, "SELECT id, value FROM visibility ORDER BY id") == [[1, "committed"]]
    assert {:ok, [["ok"]]} = Connection.pragma_query(connection, :integrity_check)
    close(reopened, connection)
  end

  test "pool and manager execute representative ordered behavior" do
    {:ok, pool} = Pool.start_link(database: :memory, pool_size: 2)

    {:ok, _} =
      Pool.execute(pool, "CREATE TABLE parity(id INTEGER PRIMARY KEY, value TEXT UNIQUE)")

    {:ok, _} = Pool.execute(pool, "INSERT INTO parity VALUES (?, ?)", [2, "b"])
    {:ok, _} = Pool.execute(pool, "INSERT INTO parity VALUES (?, ?)", [1, "a"])

    assert {:ok, %Result{rows: [[1, "a"], [2, "b"]]}} =
             Pool.query(pool, "SELECT id, value FROM parity ORDER BY id")

    :ok = Pool.stop(pool)

    {:ok, manager} = Manager.start_link(max_databases: 1)
    {:ok, managed} = Manager.open(manager, :core, :memory, pool_size: 1)
    {:ok, _} = Pool.execute(managed, "CREATE TABLE managed(value INTEGER)")
    {:ok, _} = Pool.execute(managed, "INSERT INTO managed VALUES (7)")
    assert {:ok, %Result{rows: [[7]]}} = Pool.query(managed, "SELECT value FROM managed")
    :ok = Manager.stop(manager)
  end

  defp open(:memory, _root) do
    {:ok, database} = Database.open(:memory)
    {:ok, connection} = Database.connect(database)
    {database, connection}
  end

  defp open(:file, root) do
    {:ok, database} = Database.open(tmp_path(root))
    {:ok, connection} = Database.connect(database)
    {database, connection}
  end

  defp rows(connection, sql, params \\ []) do
    {:ok, cursor} = Connection.query(connection, sql, params)
    {:ok, result} = Cursor.all(cursor, 10_000, 64)
    result.rows
  end

  defp close(database, connection, others \\ []) do
    Enum.each([connection | others], &Connection.close/1)
    Database.close(database)
  end
end
