defmodule Tursox.MultiprocessAccessTest do
  use Tursox.TestSupport.TmpCase, async: true

  alias Tursox.TestSupport.Multiprocess, as: MP
  alias Tursox.{Connection, Cursor, Database, Error}

  setup %{tmp_dir: root} do
    {:ok, root: root, path: tmp_path(root, "multiprocess.db")}
  end

  test "independent OS processes write and a Tursox reader observes sidecars", %{path: path} do
    if MP.supported?() do
      MP.run!(["init", path])
      MP.run!(["insert", path, "1", "one"])
      MP.run!(["insert", path, "2", "two"])

      {database, connection} = open(path)

      assert rows(connection, "SELECT id, value FROM process_rows ORDER BY id") ==
               [[1, "one"], [2, "two"]]

      assert File.regular?(path <> "-wal")
      assert File.regular?(path <> "-tshm")
      assert {:ok, [["ok"]]} = Connection.pragma_query(connection, :integrity_check)
      close(database, connection)
    else
      assert Tursox.Capabilities.experimental_features().multiprocess_wal.status ==
               :platform_limited
    end
  end

  test "reader snapshot stays stable across another process commit", %{root: root, path: path} do
    if MP.supported?() do
      MP.run!(["init", path])
      MP.run!(["insert", path, "1", "initial"])
      ready = tmp_path(root, "reader.ready")
      release = tmp_path(root, "reader.release")
      result = tmp_path(root, "reader.result")
      child = MP.start(["hold-reader", path, ready, release, result])
      on_exit(fn -> MP.terminate(child) end)

      assert MP.await_term(ready) == 1
      MP.run!(["insert", path, "2", "committed"])
      MP.signal(release)
      assert MP.await_term(result) == {1, 1, 2}
    end
  end

  test "writers serialize through cross-process barriers", %{root: root, path: path} do
    if MP.supported?() do
      MP.run!(["init", path])
      first_ready = tmp_path(root, "first.ready")
      first_release = tmp_path(root, "first.release")
      first_result = tmp_path(root, "first.result")
      second_ready = tmp_path(root, "second.ready")
      second_result = tmp_path(root, "second.result")

      first = MP.start(["hold-write", path, "1", first_ready, first_release, first_result])
      on_exit(fn -> MP.terminate(first) end)
      assert MP.await_term(first_ready) == :written

      second = MP.start(["contended-write", path, "2", second_ready, second_result])
      on_exit(fn -> MP.terminate(second) end)
      assert MP.await_term(second_ready) == :attempting
      refute File.exists?(second_result)

      MP.signal(first_release)
      assert MP.await_term(first_result) == :ok
      assert MP.await_term(second_result) == :ok

      {database, connection} = open(path)
      assert rows(connection, "SELECT id FROM process_rows ORDER BY id") == [[1], [2]]
      close(database, connection)
    end
  end

  test "memory and MVCC combinations are rejected", %{path: path} do
    assert {:error, %Error{code: :invalid_argument}} =
             Database.open(:memory, features: [:multiprocess_wal])

    assert {:error, %Error{code: :invalid_argument}} =
             Database.open(path,
               journal_mode: :mvcc,
               features: [:multiprocess_wal]
             )
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
