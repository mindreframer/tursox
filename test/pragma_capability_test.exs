defmodule Tursox.PragmaCapabilityTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.{Connection, Database, Error, Native}

  setup %{tmp_dir: root} do
    baseline = Native.resource_snapshot()
    path = tmp_path(root)
    {:ok, database} = Database.open(path)
    {:ok, connection} = Database.connect(database)

    on_exit(fn ->
      Connection.close(connection)
      Database.close(database)
      assert baseline == Native.resource_snapshot()
    end)

    {:ok, database: database, connection: connection, path: path}
  end

  test "metadata pragmas expose stable one-row shapes", %{connection: connection} do
    for name <- [:page_count, :page_size, :max_page_count, :freelist_count, :schema_version] do
      assert {:ok, [[value]]} = Connection.pragma_query(connection, name)
      assert is_integer(value) and value >= 0
    end

    assert {:ok, [["UTF-8"]]} = Connection.pragma_query(connection, :encoding)
    assert {:ok, [[0]]} = Connection.pragma_query(connection, :application_id)
    assert {:ok, [[0]]} = Connection.pragma_query(connection, :user_version)
    assert {:ok, []} = Connection.pragma_update(connection, :page_size, 8_192)
    assert {:ok, [[8_192]]} = Connection.pragma_query(connection, :page_size)
    assert {:ok, [[0, "main", file]]} = Connection.pragma_query(connection, :database_list)
    assert is_binary(file)

    assert {:ok, []} = Connection.pragma_update(connection, :application_id, 0x5458)
    assert {:ok, [[0x5458]]} = Connection.pragma_query(connection, :application_id)
    assert {:ok, []} = Connection.pragma_update(connection, :user_version, 200)
    assert {:ok, [[200]]} = Connection.pragma_query(connection, :user_version)
    assert {:ok, [[20_000]]} = Connection.pragma_update(connection, :max_page_count, 20_000)
  end

  test "schema and index introspection safely quotes arbitrary identifiers", %{
    connection: connection
  } do
    table = ~s(odd"; DROP TABLE sentinel; --)
    index = ~s(idx"; DROP TABLE sentinel; --)
    normalized_table = String.downcase(table)
    normalized_index = String.downcase(index)
    :ok = Connection.execute(connection, "CREATE TABLE sentinel(value INTEGER)")

    :ok =
      Connection.execute(
        connection,
        ~S|CREATE TABLE "odd""; DROP TABLE sentinel; --" (id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT 'x')|
      )

    :ok =
      Connection.execute(
        connection,
        ~S|CREATE UNIQUE INDEX "idx""; DROP TABLE sentinel; --" ON "odd""; DROP TABLE sentinel; --"(name)|
      )

    assert {:ok,
            [
              [0, "id", "INTEGER", 0, nil, 1],
              [1, "name", "TEXT", 1, "'x'", 0]
            ]} = Connection.pragma_query(connection, :table_info, {:identifier, table})

    assert {:ok, xinfo} = Connection.pragma_query(connection, :table_xinfo, {:identifier, table})
    assert Enum.all?(xinfo, &(length(&1) == 7))

    assert {:ok, [[0, ^normalized_index, 1, "c", 0]]} =
             Connection.pragma_query(connection, :index_list, {:identifier, table})

    assert {:ok, [[0, 1, "name"]]} =
             Connection.pragma_query(connection, :index_info, {:identifier, index})

    assert {:ok, index_xinfo} =
             Connection.pragma_query(connection, :index_xinfo, {:identifier, index})

    assert Enum.all?(index_xinfo, &(length(&1) == 6))
    assert {:ok, table_list} = Connection.pragma_query(connection, :table_list)
    assert Enum.any?(table_list, fn row -> Enum.at(row, 1) == normalized_table end)
    assert {:ok, [[0]]} = query_count(connection, "sentinel")

    assert {:error, %Error{code: :invalid_argument}} =
             Connection.pragma_query(connection, :table_info, {:identifier, "bad\0name"})
  end

  test "function and pragma inventories have documented ordered widths", %{connection: connection} do
    assert {:ok, functions} = Connection.pragma_query(connection, :function_list)
    assert functions != []
    assert Enum.all?(functions, &(length(&1) == 6))
    assert Enum.any?(functions, fn [name | _] -> name == "json_extract" end)

    assert {:ok, pragmas} = Connection.pragma_query(connection, :pragma_list)
    assert pragmas != []
    assert Enum.all?(pragmas, &(length(&1) == 1))

    names = MapSet.new(pragmas, fn [name] -> name end)

    for name <- ~w(database_list page_count page_size max_page_count freelist_count encoding
                   schema_version application_id user_version table_info table_xinfo table_list
                   index_list index_info index_xinfo function_list journal_mode cache_size
                   cache_spill synchronous temp_store busy_timeout query_only foreign_keys
                   ignore_check_constraints data_sync_retry require_where integrity_check quick_check
                   wal_checkpoint list_types) do
      assert MapSet.member?(names, name), "#{name} missing from PRAGMA pragma_list"
    end

    # 0.7.2 executes this introspection pragma but omits itself from its inventory.
    refute MapSet.member?(names, "pragma_list")
  end

  test "configuration scope and persistence are explicit", %{
    database: database,
    connection: first,
    path: path
  } do
    {:ok, second} = Database.connect(database)

    for {name, value, expected} <- [
          {:cache_size, 2_000, 2_000},
          {:cache_spill, false, 0},
          {:synchronous, :off, 0},
          {:temp_store, 2, 2},
          {:busy_timeout, 50, 50},
          {:query_only, true, 1},
          {:foreign_keys, true, 1},
          {:ignore_check_constraints, true, 1},
          {:data_sync_retry, true, 1},
          {:require_where, true, 1}
        ] do
      assert {:ok, _rows} = Connection.pragma_update(first, name, value)
      assert {:ok, [[^expected]]} = Connection.pragma_query(first, name)
    end

    assert {:ok, [[0]]} = Connection.pragma_query(second, :query_only)
    assert {:ok, [[0]]} = Connection.pragma_query(second, :foreign_keys)
    assert {:ok, [[0]]} = Connection.pragma_query(second, :require_where)
    assert {:ok, []} = Connection.pragma_update(second, :i_am_a_dummy, true)
    assert {:ok, [[1]]} = Connection.pragma_query(second, :require_where)

    assert {:error, %Error{code: :misuse}} =
             Connection.execute(first, "CREATE TABLE blocked(value INTEGER)")

    assert {:ok, []} = Connection.pragma_update(first, :query_only, false)
    :ok = Connection.execute(first, "CREATE TABLE checks(value INTEGER CHECK(value > 0))")
    :ok = Connection.execute(first, "INSERT INTO checks VALUES (-1)")
    assert {:ok, []} = Connection.pragma_update(first, :ignore_check_constraints, false)

    assert {:error, %Error{code: :constraint}} =
             Connection.execute(first, "INSERT INTO checks VALUES (-2)")

    :ok = Connection.execute(first, "CREATE TABLE guarded(value INTEGER)")
    assert {:error, %Error{}} = Connection.execute(first, "DELETE FROM guarded")
    assert :ok = Connection.execute(first, "DELETE FROM guarded WHERE value = 1")

    assert {:ok, []} = Connection.pragma_update(first, :application_id, 901)
    assert {:ok, []} = Connection.pragma_update(first, :user_version, 202)
    Connection.close(second)
    Connection.close(first)
    Database.close(database)

    {:ok, reopened} = Database.open(path)
    {:ok, reopened_connection} = Database.connect(reopened)
    assert {:ok, [[901]]} = Connection.pragma_query(reopened_connection, :application_id)
    assert {:ok, [[202]]} = Connection.pragma_query(reopened_connection, :user_version)
    assert {:ok, [[0]]} = Connection.pragma_query(reopened_connection, :query_only)
    Connection.close(reopened_connection)
    Database.close(reopened)
  end

  test "integrity, WAL, MVCC, gated and unavailable pragmas are classified", %{
    connection: connection,
    tmp_dir: root
  } do
    :ok =
      Connection.execute(connection, "CREATE TABLE workload(id INTEGER PRIMARY KEY, value TEXT)")

    for id <- 1..50 do
      :ok = Connection.execute(connection, "INSERT INTO workload VALUES (?, ?)", [id, "v#{id}"])
    end

    assert {:ok, [["ok"]]} = Connection.pragma_query(connection, :quick_check)
    assert {:ok, [["ok"]]} = Connection.pragma_query(connection, :integrity_check)
    assert {:ok, [["ok"]]} = Connection.pragma_query(connection, :integrity_check, 10)

    assert {:ok, [[busy, log, checkpointed]]} =
             Connection.pragma_query(connection, :wal_checkpoint)

    assert Enum.all?([busy, log, checkpointed], &is_integer/1)

    assert {:ok, []} = Connection.pragma_query(connection, :legacy_file_format)
    assert {:ok, []} = Connection.pragma_query(connection, :capture_data_changes_conn, "full")
    assert {:ok, []} = Connection.pragma_query(connection, :cipher)
    assert {:ok, _} = Connection.pragma_query(connection, :hexkey)
    assert {:error, %Error{}} = Connection.pragma_query(connection, :mvcc_checkpoint_threshold)
    assert {:error, %Error{}} = Connection.pragma_query(connection, :mvcc_gc_threshold)

    {:ok, mvcc} = Database.open(tmp_path(root, "mvcc.db"), journal_mode: :mvcc)
    {:ok, mvcc_connection} = Database.connect(mvcc)
    assert {:ok, []} = Connection.pragma_update(mvcc_connection, :mvcc_checkpoint_threshold, 64)
    assert {:ok, [[64]]} = Connection.pragma_query(mvcc_connection, :mvcc_checkpoint_threshold)
    assert {:ok, []} = Connection.pragma_update(mvcc_connection, :mvcc_gc_threshold, 32)
    assert {:ok, [[32]]} = Connection.pragma_query(mvcc_connection, :mvcc_gc_threshold)
    Connection.close(mvcc_connection)
    Database.close(mvcc)
  end

  test "hazardous MVCC checkpoint path is contained by a disposable BEAM", %{tmp_dir: root} do
    project = File.cwd!()

    {output, status} =
      System.cmd(
        "mix",
        [
          "run",
          "--no-compile",
          "bin/capability_probe.exs",
          "mvcc-manual-checkpoint",
          tmp_path(root, "probe.db")
        ],
        cd: project,
        env: [{"MIX_ENV", "test"}, {"TURSOX_BUILD", "1"}, {"ERL_FLAGS", "+sssdio 64"}],
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "unsupported:mvcc_manual_checkpoint"
  end

  test "pragma validation rejects fragments and invalid argument shapes", %{
    connection: connection
  } do
    for call <- [
          fn ->
            Connection.pragma_query(connection, "table_info; DROP TABLE x", {:identifier, "x"})
          end,
          fn -> Connection.pragma_query(connection, :table_info, {:identifier, ""}) end,
          fn -> Connection.pragma_query(connection, :integrity_check, -1) end,
          fn ->
            Connection.pragma_query(connection, :integrity_check, {:raw, "1); DROP TABLE x"})
          end,
          fn -> Connection.pragma_update(connection, :journal_mode, :unknown) end
        ] do
      assert {:error, %Error{code: :invalid_argument}} = call.()
    end
  end

  defp query_count(connection, table) do
    {:ok, cursor} = Connection.query(connection, "SELECT COUNT(*) FROM \"#{table}\"")
    {:ok, result} = Tursox.Cursor.all(cursor, 1, 1)
    {:ok, result.rows}
  end
end
