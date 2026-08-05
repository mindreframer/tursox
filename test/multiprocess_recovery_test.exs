defmodule Tursox.MultiprocessRecoveryTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.TestSupport.Multiprocess, as: MP
  alias Tursox.{Connection, Cursor, Database, Statement}

  @moduletag timeout: 8_000

  setup %{tmp_dir: root} do
    workers = if MP.supported?(), do: MP.nodes(), else: [nil, nil]
    {:ok, root: root, path: tmp_path(root, "recovery.db"), workers: workers}
  end

  test "killed writer rolls back and a new process recovers the writer slot", %{
    root: root,
    path: path,
    workers: [doomed, survivor]
  } do
    if MP.supported?() do
      MP.run!(survivor, ["init", path])
      ready = tmp_path(root, "crash.ready")
      child = MP.start(doomed, ["hold-uncommitted", path, "99", ready])
      assert MP.await_term(ready) == :uncommitted
      assert :ok = MP.kill(child)

      replacement = MP.replace(doomed)
      refute replacement in [doomed, survivor]
      assert Node.ping(survivor) == :pong
      MP.run!(replacement, ["insert", path, "1", "recovered"])
      {database, connection} = open(path)

      assert rows(connection, "SELECT id, value FROM process_rows ORDER BY id") ==
               [[1, "recovered"]]

      assert {:ok, [["ok"]]} = Connection.pragma_query(connection, :integrity_check)
      close(database, connection)
    end
  end

  test "0.7.2 does not enforce documented live mode-mixing rejection", %{
    root: root,
    path: path,
    workers: [worker | _]
  } do
    if MP.supported?() do
      MP.run!(worker, ["init", path])
      ready = tmp_path(root, "open.ready")
      release = tmp_path(root, "open.release")
      child = MP.start(worker, ["hold-open", path, ready, release])
      on_exit(fn -> MP.terminate(child) end)
      assert MP.await_term(ready) == :open

      # Documentation newer than the pin promises rejection. On 0.7.2/macOS the
      # legacy open succeeds, so Tursox records the limitation and avoids mixing
      # operations rather than claiming coordination.
      assert {:ok, mixed} = Database.open(path)
      assert Database.metadata(mixed).features == []
      Database.close(mixed)
      MP.signal(release)
      assert {:ok, :ok} = MP.await_exit(child)

      {:ok, database} = Database.open(path)
      {:ok, connection} = Database.connect(database)
      assert rows(connection, "SELECT COUNT(*) FROM process_rows") == [[0]]
      close(database, connection)
    end
  end

  test "cross-process checkpoint and schema change refresh existing statements", %{
    root: root,
    path: path,
    workers: [first, second]
  } do
    if MP.supported?() do
      MP.run!(first, ["init", path])
      MP.run!(second, ["insert", path, "1", "before-schema"])
      {database, connection} = open(path)

      {:ok, statement} =
        Connection.prepare(connection, "SELECT id, value FROM process_rows ORDER BY id")

      MP.run!(second, ["schema", path])
      {:ok, cursor} = Statement.query(statement)
      {:ok, result} = Cursor.all(cursor, 10, 2)
      assert result.rows == [[1, "before-schema"]]
      Statement.close(statement)

      checkpoint_result = tmp_path(root, "checkpoint.result")
      MP.run!(first, ["checkpoint", path, checkpoint_result])
      assert {:ok, [[busy, log, checkpointed]]} = MP.await_term(checkpoint_result)
      assert Enum.all?([busy, log, checkpointed], &is_integer/1)
      assert {:ok, [["ok"]]} = Connection.pragma_query(connection, :quick_check)
      close(database, connection)
    end
  end

  test "platform preflight is explicit" do
    status = Tursox.Capabilities.experimental_features().multiprocess_wal.status
    assert status == :platform_limited

    if MP.supported?() do
      assert match?({:unix, _}, :os.type())
      assert :erlang.system_info(:wordsize) == 8
    else
      refute MP.supported?()
    end
  end

  defp open(path) do
    {:ok, database} = Database.open(path, features: [:multiprocess_wal], busy_timeout: 5_000)
    {:ok, connection} = Database.connect(database, busy_timeout: 5_000)
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
