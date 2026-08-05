defmodule Tursox.DatabaseConnectionTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.{Connection, Database, Error, Native}

  test "one database derives multiple connections sharing memory", %{tmp_dir: _tmp_dir} do
    baseline = Native.resource_snapshot()
    {:ok, database} = Database.open(:memory)
    {:ok, first} = Database.connect(database, busy_timeout: 25)
    {:ok, second} = Database.connect(database)

    snapshot = Native.resource_snapshot()
    assert snapshot.databases == baseline.databases + 1
    assert snapshot.connections == baseline.connections + 2

    assert {:ok, []} = Connection.pragma_update(first, :user_version, 42)
    assert {:ok, [[42]]} = Connection.pragma_query(second, :user_version)
    assert {:ok, :idle} = Connection.status(first)
    assert :ok = Connection.cache_flush(first)

    assert :ok = Connection.close(first)
    assert :ok = Connection.close(first)
    assert :ok = Connection.close(second)
    assert :ok = Database.close(database)
    assert :ok = Database.close(database)
    assert baseline == Native.resource_snapshot()
  end

  test "separate memory databases are isolated" do
    baseline = Native.resource_snapshot()
    {:ok, first_db} = Database.open(:memory)
    {:ok, second_db} = Database.open(:memory)
    {:ok, first} = Database.connect(first_db)
    {:ok, second} = Database.connect(second_db)

    assert {:ok, []} = Connection.pragma_update(first, :user_version, 7)
    assert {:ok, [[7]]} = Connection.pragma_query(first, :user_version)
    assert {:ok, [[0]]} = Connection.pragma_query(second, :user_version)

    Enum.each([first, second], &Connection.close/1)
    Enum.each([first_db, second_db], &Database.close/1)
    assert baseline == Native.resource_snapshot()
  end

  test "file databases persist and normalize Unicode paths", %{tmp_dir: tmp_dir} do
    baseline = Native.resource_snapshot()
    path = Path.join([tmp_dir, "missing", "dåtabase-数据库.db"])

    assert {:error, %Error{code: :invalid_argument}} = Database.open(path)
    assert baseline == Native.resource_snapshot()

    {:ok, database} = Database.open(path, create_parent: true)
    assert Database.metadata(database).path == Path.expand(path)
    {:ok, connection} = Database.connect(database)
    assert {:ok, []} = Connection.pragma_update(connection, :user_version, 91)
    :ok = Connection.cache_flush(connection)
    :ok = Connection.close(connection)
    :ok = Database.close(database)

    {:ok, reopened} = Database.open(path)
    {:ok, connection} = Database.connect(reopened)
    assert {:ok, [[91]]} = Connection.pragma_query(connection, :user_version)
    :ok = Connection.close(connection)
    :ok = Database.close(reopened)
    assert baseline == Native.resource_snapshot()
  end

  test "parent close safely invalidates descendants" do
    baseline = Native.resource_snapshot()
    {:ok, database} = Database.open(:memory)
    {:ok, connection} = Database.connect(database)

    assert :ok = Database.close(database)

    assert {:error, %Error{code: :closed, operation: :connection_status}} =
             Connection.status(connection)

    assert {:error, %Error{code: :closed}} = Database.connect(database)
    assert :ok = Connection.close(connection)
    assert baseline == Native.resource_snapshot()
  end

  test "invalid options and unsupported open modes allocate no resources" do
    baseline = Native.resource_snapshot()

    assert {:error, %Error{code: :invalid_argument}} = Database.open(:memory, unknown: true)
    assert {:error, %Error{code: :invalid_argument}} = Database.open(:memory, features: "attach")

    assert {:error, %Error{code: :unsupported}} =
             Database.open(:memory, features: [:future_feature])

    assert {:error, %Error{code: :unsupported}} = Database.open(:memory, mode: :read_only)

    assert {:error, %Error{code: :invalid_argument}} =
             Database.open(:memory,
               journal_mode: :mvcc,
               features: [:multiprocess_wal]
             )

    assert baseline == Native.resource_snapshot()
  end

  test "confirmed builder switches are explicit and accepted" do
    assert :attach in Database.builder_features()
    refute :mvcc_passive_checkpoint in Database.builder_features()

    baseline = Native.resource_snapshot()
    {:ok, database} = Database.open(:memory, features: [:index_method, :without_rowid])
    assert Database.metadata(database).features == [:index_method, :without_rowid]
    :ok = Database.close(database)

    assert {:error, %Error{code: :unsupported}} =
             Database.open(:memory, features: [:mvcc_passive_checkpoint])

    {:ok, mvcc} = Database.open(:memory, journal_mode: :mvcc)
    assert Database.metadata(mvcc).journal_mode == :mvcc
    :ok = Database.close(mvcc)
    assert baseline == Native.resource_snapshot()
  end

  test "many databases and concurrent connection creation remain isolated" do
    baseline = Native.resource_snapshot()

    databases =
      for index <- 1..101 do
        {:ok, database} = Database.open(:memory)
        {:ok, connection} = Database.connect(database)
        {:ok, []} = Connection.pragma_update(connection, :user_version, index)
        :ok = Connection.close(connection)
        database
      end

    assert Native.resource_snapshot().databases == baseline.databases + 101

    database = hd(databases)

    connections =
      1..16
      |> Task.async_stream(fn _ -> Database.connect(database) end, ordered: false)
      |> Enum.map(fn {:ok, {:ok, connection}} -> connection end)

    assert Enum.all?(connections, fn connection ->
             Connection.pragma_query(connection, :user_version) == {:ok, [[1]]}
           end)

    Enum.each(connections, &Connection.close/1)
    Enum.each(databases, &Database.close/1)
    assert baseline == Native.resource_snapshot()
  end

  test "pragma validation does not accept SQL fragments" do
    {:ok, database} = Database.open(:memory)
    {:ok, connection} = Database.connect(database)

    assert {:error, %Error{code: :invalid_argument}} =
             Connection.pragma_query(connection, "user_version; DROP TABLE x")

    :ok = Connection.close(connection)
    :ok = Database.close(database)
  end
end
