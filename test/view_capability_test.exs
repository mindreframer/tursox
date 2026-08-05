defmodule Tursox.ViewCapabilityTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.{Connection, Cursor, Database, Error, Native}

  setup %{tmp_dir: root} do
    baseline = Native.resource_snapshot()
    on_exit(fn -> assert baseline == Native.resource_snapshot() end)
    {:ok, root: root}
  end

  test "ordinary views create, filter, aggregate, introspect, reject writes, and drop" do
    {database, connection} = open(:memory)

    :ok =
      Connection.execute_batch(connection, """
      CREATE TABLE orders(id INTEGER PRIMARY KEY, customer TEXT, amount INTEGER);
      INSERT INTO orders VALUES (1, 'Ada', 5), (2, 'Ada', 7), (3, 'Grace', 3);
      CREATE VIEW large_orders AS
        SELECT id, customer, amount FROM orders WHERE amount >= 5;
      CREATE VIEW customer_totals AS
        SELECT customer, COUNT(*) AS count, SUM(amount) AS total
        FROM orders GROUP BY customer;
      """)

    assert rows(connection, "SELECT * FROM large_orders ORDER BY id") ==
             [[1, "Ada", 5], [2, "Ada", 7]]

    assert rows(connection, "SELECT * FROM customer_totals ORDER BY customer") ==
             [["Ada", 2, 12], ["Grace", 1, 3]]

    assert {:error, %Error{}} =
             Connection.execute(connection, "INSERT INTO large_orders VALUES (4, 'Lin', 9)")

    assert Enum.any?(rows(connection, "PRAGMA table_list"), fn
             ["main", "large_orders", "view", 3, 0, 0] -> true
             _ -> false
           end)

    :ok = Connection.execute(connection, "DROP VIEW large_orders")
    assert {:error, %Error{}} = Connection.query(connection, "SELECT * FROM large_orders")
    assert rows(connection, "SELECT COUNT(*) FROM orders") == [[3]]
    close(database, connection)
  end

  test "materialized views are gated and unsafe enabled definitions stay in subprocesses", %{
    root: root
  } do
    {database, connection} = open(tmp_path(root, "disabled.db"))
    :ok = Connection.execute(connection, "CREATE TABLE base(value INTEGER)")

    assert {:error, %Error{code: :misuse}} =
             Connection.execute(
               connection,
               "CREATE MATERIALIZED VIEW materialized AS SELECT value FROM base"
             )

    assert {:ok, [["ok"]]} = Connection.pragma_query(connection, :integrity_check)
    close(database, connection)

    case run_materialized_probe(tmp_path(root, "enabled.db")) do
      {:ok, {output, 0}} -> assert output =~ "result:materialized_views:"
      {:ok, {_output, status}} -> assert status > 0
      :timeout -> flunk("materialized view probe exceeded its 15 second bound")
    end
  end

  defp run_materialized_probe(path) do
    task =
      Task.async(fn ->
        System.cmd(
          "mix",
          [
            "run",
            "--no-compile",
            "bin/capability_probe.exs",
            "experimental-sql",
            "materialized_views",
            path
          ],
          cd: File.cwd!(),
          env: [{"MIX_ENV", "test"}, {"TURSOX_BUILD", "1"}, {"ERL_FLAGS", "+sssdio 64"}],
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, 15_000) do
      {:ok, result} ->
        {:ok, result}

      nil ->
        Task.shutdown(task, :brutal_kill)
        :timeout
    end
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
