defmodule Tursox.TransactionMvccTest do
  use ExUnit.Case, async: false

  alias Tursox.{Connection, Cursor, Database, Error, Native}

  setup_all do
    root = Path.join(System.tmp_dir!(), "tursox-mvcc-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  setup %{root: root} do
    tmp_dir = Path.join(root, Integer.to_string(System.unique_integer([:positive, :monotonic])))
    File.mkdir_p!(tmp_dir)
    {:ok, tmp_dir: tmp_dir}
  end

  test "all stable transaction modes transition status and commit", %{tmp_dir: tmp_dir} do
    baseline = Native.resource_snapshot()
    {:ok, database} = Database.open(tmp_path(tmp_dir))
    {:ok, connection} = Database.connect(database)
    :ok = Connection.execute(connection, "CREATE TABLE modes (value TEXT)")

    for mode <- [:deferred, :immediate, :exclusive] do
      assert :ok = Connection.begin(connection, mode: mode)
      assert {:ok, :transaction} = Connection.status(connection)

      assert :ok =
               Connection.execute(connection, "INSERT INTO modes VALUES (?)", [
                 Atom.to_string(mode)
               ])

      assert :ok = Connection.commit(connection)
      assert {:ok, :idle} = Connection.status(connection)
    end

    assert rows(connection, "SELECT value FROM modes ORDER BY rowid") ==
             [["deferred"], ["immediate"], ["exclusive"]]

    assert {:error, %Error{code: :unsupported}} = Connection.begin(connection, mode: :concurrent)

    close_all([connection], database)
    assert baseline == Native.resource_snapshot()
  end

  test "callback failures, raises, throws, exits, and nesting roll back" do
    {:ok, database} = Database.open(:memory)
    {:ok, connection} = Database.connect(database)
    :ok = Connection.execute(connection, "CREATE TABLE rollback_test (value INTEGER)")

    assert {:error, :stop} =
             Connection.transaction(connection, fn ->
               :ok = Connection.execute(connection, "INSERT INTO rollback_test VALUES (1)")
               {:error, :stop}
             end)

    assert_raise RuntimeError, "boom", fn ->
      Connection.transaction(connection, fn ->
        :ok = Connection.execute(connection, "INSERT INTO rollback_test VALUES (2)")
        raise "boom"
      end)
    end

    assert catch_throw(
             Connection.transaction(connection, fn ->
               :ok = Connection.execute(connection, "INSERT INTO rollback_test VALUES (3)")
               throw(:thrown)
             end)
           ) == :thrown

    assert catch_exit(
             Connection.transaction(connection, fn ->
               :ok = Connection.execute(connection, "INSERT INTO rollback_test VALUES (4)")
               exit(:exited)
             end)
           ) == :exited

    assert {:error, %Error{code: :misuse}} =
             Connection.transaction(connection, fn -> Connection.begin(connection) end)

    assert rows(connection, "SELECT COUNT(*) FROM rollback_test") == [[0]]
    assert {:ok, :idle} = Connection.status(connection)
    close_all([connection], database)
  end

  test "MVCC concurrent disjoint writers commit from separate connections", %{tmp_dir: tmp_dir} do
    baseline = Native.resource_snapshot()
    {:ok, database} = Database.open(tmp_path(tmp_dir), journal_mode: :mvcc)
    {:ok, first} = Database.connect(database)
    {:ok, second} = Database.connect(database)
    :ok = Connection.execute(first, "CREATE TABLE writes (id INTEGER PRIMARY KEY, value INTEGER)")

    :ok =
      Connection.execute_batch(
        first,
        "INSERT INTO writes VALUES (1, 0); INSERT INTO writes VALUES (2, 0)"
      )

    parent = self()
    writer1 = writer_task(parent, first, 1)
    writer2 = writer_task(parent, second, 2)
    assert_receive {:ready, ^writer1}
    assert_receive {:ready, ^writer2}
    send(writer1, :write)
    send(writer2, :write)
    assert_receive {:written, ^writer1, :ok}
    assert_receive {:written, ^writer2, :ok}
    send(writer1, :commit)
    send(writer2, :commit)
    assert_receive {:committed, ^writer1, :ok}
    assert_receive {:committed, ^writer2, :ok}

    assert rows(first, "SELECT id, value FROM writes ORDER BY id") == [[1, 1], [2, 1]]
    close_all([first, second], database)
    assert baseline == Native.resource_snapshot()
  end

  test "same-row MVCC conflict is retryable and losing transaction rolls back", %{
    tmp_dir: tmp_dir
  } do
    {:ok, database} = Database.open(tmp_path(tmp_dir), journal_mode: :mvcc)
    {:ok, first} = Database.connect(database)
    {:ok, second} = Database.connect(database)

    :ok =
      Connection.execute(
        first,
        "CREATE TABLE conflict_test (id INTEGER PRIMARY KEY, value INTEGER)"
      )

    :ok = Connection.execute(first, "INSERT INTO conflict_test VALUES (1, 0)")

    :ok = Connection.begin(first, mode: :concurrent)
    :ok = Connection.begin(second, mode: :concurrent)
    assert rows(first, "SELECT value FROM conflict_test WHERE id = 1") == [[0]]
    assert rows(second, "SELECT value FROM conflict_test WHERE id = 1") == [[0]]
    :ok = Connection.execute(first, "UPDATE conflict_test SET value = 10 WHERE id = 1")

    error =
      case Connection.execute(second, "UPDATE conflict_test SET value = 20 WHERE id = 1") do
        {:error, %Error{} = error} ->
          _ = Connection.rollback(second)
          :ok = Connection.commit(first)
          error

        :ok ->
          :ok = Connection.commit(first)
          {:error, %Error{} = error} = Connection.commit(second)
          _ = Connection.rollback(second)
          error
      end

    assert Error.retryable?(error)
    assert error.code in [:busy_snapshot, :busy]
    assert {:ok, :idle} = Connection.status(second)
    assert rows(first, "SELECT value FROM conflict_test WHERE id = 1") == [[10]]

    close_all([first, second], database)
  end

  test "MVCC readers retain a stable snapshot while a writer commits", %{tmp_dir: tmp_dir} do
    {:ok, database} = Database.open(tmp_path(tmp_dir), journal_mode: :mvcc)
    {:ok, reader} = Database.connect(database)
    {:ok, writer} = Database.connect(database)
    :ok = Connection.execute(writer, "CREATE TABLE snapshot_test (value INTEGER)")
    :ok = Connection.execute(writer, "INSERT INTO snapshot_test VALUES (1)")

    :ok = Connection.begin(reader, mode: :concurrent)
    assert rows(reader, "SELECT value FROM snapshot_test") == [[1]]

    assert {:ok, :updated} =
             Connection.transaction(
               writer,
               fn ->
                 :ok = Connection.execute(writer, "UPDATE snapshot_test SET value = 2")
                 :updated
               end,
               mode: :concurrent
             )

    assert rows(reader, "SELECT value FROM snapshot_test") == [[1]]
    :ok = Connection.commit(reader)
    assert rows(reader, "SELECT value FROM snapshot_test") == [[2]]
    close_all([reader, writer], database)
  end

  test "whole-transaction retry obeys bounds and classes" do
    {:ok, database} = Database.open(:memory, journal_mode: :mvcc)
    {:ok, connection} = Database.connect(database)
    :ok = Connection.execute(connection, "CREATE TABLE retry_test (value INTEGER)")
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    assert {:ok, :inserted} =
             Connection.retry_transaction(
               connection,
               fn ->
                 attempt = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})

                 if attempt < 3 do
                   {:error,
                    %Error{code: :busy_snapshot, operation: :test_conflict, message: "conflict"}}
                 else
                   :ok = Connection.execute(connection, "INSERT INTO retry_test VALUES (1)")
                   :inserted
                 end
               end,
               mode: :concurrent,
               attempts: 3,
               backoff: fn attempt, _error -> attempt - 1 end,
               jitter: & &1
             )

    assert Agent.get(counter, & &1) == 3
    assert rows(connection, "SELECT COUNT(*) FROM retry_test") == [[1]]

    Agent.update(counter, fn _ -> 0 end)

    assert {:error, %Error{code: :constraint}} =
             Connection.retry_transaction(
               connection,
               fn ->
                 Agent.update(counter, &(&1 + 1))
                 {:error, %Error{code: :constraint, operation: :test, message: "no retry"}}
               end,
               attempts: 5
             )

    assert Agent.get(counter, & &1) == 1
    Agent.stop(counter)
    close_all([connection], database)
  end

  test "checkpoint threshold, passive checkpoint, integrity, and reopen are executable", %{
    tmp_dir: tmp_dir
  } do
    path = tmp_path(tmp_dir)

    IO.puts(:stderr, "checkpoint debug: native database open")
    {:ok, native_database} = Native.database_open(path, [])
    IO.puts(:stderr, "checkpoint debug: native connection open")
    {:ok, native_connection} = Native.database_connect(native_database, 0)
    IO.puts(:stderr, "checkpoint debug: native journal update")
    {:ok, _} = Native.connection_pragma_update(native_connection, "journal_mode", "mvcc")
    IO.puts(:stderr, "checkpoint debug: native journal query")
    {:ok, _} = Native.connection_pragma_query(native_connection, "journal_mode")
    IO.puts(:stderr, "checkpoint debug: native close")
    :ok = Native.connection_close(native_connection)
    :ok = Native.database_close(native_database)

    IO.puts(:stderr, "checkpoint debug: open mvcc")
    {:ok, database} = Database.open(path, journal_mode: :mvcc)
    IO.puts(:stderr, "checkpoint debug: connect mvcc")
    {:ok, connection} = Database.connect(database)
    IO.puts(:stderr, "checkpoint debug: threshold")
    assert {:ok, 64} = Connection.set_mvcc_checkpoint_threshold(connection, 64)
    IO.puts(:stderr, "checkpoint debug: create")
    :ok = Connection.execute(connection, "CREATE TABLE durable (value TEXT)")
    IO.puts(:stderr, "checkpoint debug: insert")
    :ok = Connection.execute(connection, "INSERT INTO durable VALUES ('kept')")

    IO.puts(:stderr, "checkpoint debug: reject manual checkpoint")

    assert {:error, %Error{code: :unsupported}} =
             Connection.checkpoint(connection, :passive)

    IO.puts(:stderr, "checkpoint debug: integrity")
    assert rows(connection, "PRAGMA integrity_check") == [["ok"]]
    IO.puts(:stderr, "checkpoint debug: close mvcc")
    close_all([connection], database)

    IO.puts(:stderr, "checkpoint debug: reopen mvcc")
    {:ok, reopened} = Database.open(path, journal_mode: :mvcc)
    {:ok, connection} = Database.connect(reopened)
    IO.puts(:stderr, "checkpoint debug: read reopened")
    assert rows(connection, "SELECT value FROM durable") == [["kept"]]
    IO.puts(:stderr, "checkpoint debug: close reopened")
    close_all([connection], reopened)

    IO.puts(:stderr, "checkpoint debug: open wal")
    {:ok, wal} = Database.open(Path.join(tmp_dir, "wal.db"), journal_mode: :wal)
    {:ok, connection} = Database.connect(wal)
    IO.puts(:stderr, "checkpoint debug: create wal")
    :ok = Connection.execute(connection, "CREATE TABLE checkpointed (value INTEGER)")

    IO.puts(:stderr, "checkpoint debug: manual wal checkpoint")

    assert {:ok, [[busy, log_frames, checkpointed_frames]]} =
             Connection.checkpoint(connection, :passive)

    assert Enum.all?([busy, log_frames, checkpointed_frames], &is_integer/1)
    IO.puts(:stderr, "checkpoint debug: close wal")
    close_all([connection], wal)
    IO.puts(:stderr, "checkpoint debug: done")
  end

  defp writer_task(parent, connection, id) do
    spawn_link(fn ->
      :ok = Connection.begin(connection, mode: :concurrent)
      send(parent, {:ready, self()})
      receive do: (:write -> :ok)

      result =
        Connection.execute(connection, "UPDATE writes SET value = value + 1 WHERE id = ?", [id])

      send(parent, {:written, self(), result})
      receive do: (:commit -> :ok)
      send(parent, {:committed, self(), Connection.commit(connection)})
    end)
  end

  defp tmp_path(root), do: Path.join(root, "database.db")

  defp rows(connection, sql) do
    {:ok, cursor} = Connection.query(connection, sql)
    {:ok, result} = Cursor.all(cursor, 10_000, 100)
    result.rows
  end

  defp close_all(connections, database) do
    Enum.each(connections, &Connection.close/1)
    Database.close(database)
  end
end
