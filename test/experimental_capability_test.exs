defmodule Tursox.ExperimentalCapabilityTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.{Capabilities, Connection, Cursor, Database, Error, Native}

  setup %{tmp_dir: root} do
    baseline = Native.resource_snapshot()
    on_exit(fn -> assert baseline == Native.resource_snapshot() end)
    {:ok, root: root}
  end

  test "machine-readable matrix is complete and aligned with builder options" do
    matrix = Capabilities.experimental_features()

    assert Map.keys(matrix) |> Enum.sort() ==
             ~w(attach autovacuum custom_types encryption generated_columns index_method
                materialized_views multiprocess_wal mvcc_passive_checkpoint strict triggers vacuum
                views without_rowid)a
             |> Enum.sort()

    assert Enum.all?(matrix, fn {_name, entry} -> entry.status in Capabilities.statuses() end)

    exposed =
      matrix
      |> Enum.flat_map(fn {_name, entry} -> if entry.option, do: [entry.option], else: [] end)
      |> Enum.sort()

    assert Enum.sort(Database.builder_features()) == exposed

    assert matrix.encryption.builder == :experimental_encryption
    assert matrix.encryption.option == nil
    assert matrix.mvcc_passive_checkpoint.option == nil
    assert matrix.strict.builder == nil
    assert matrix.triggers.builder == nil
  end

  test "always-on views, STRICT tables, and triggers require no feature flag" do
    {database, connection} = open(:memory)

    :ok =
      Connection.execute(
        connection,
        "CREATE TABLE base(id INTEGER PRIMARY KEY, value INTEGER) STRICT"
      )

    :ok = Connection.execute(connection, "CREATE VIEW ordinary AS SELECT id, value FROM base")

    :ok =
      Connection.execute_batch(connection, """
      CREATE TABLE audit(value INTEGER);
      CREATE TRIGGER base_insert AFTER INSERT ON base
      BEGIN
        INSERT INTO audit VALUES (new.value);
      END;
      INSERT INTO base VALUES (1, 7);
      """)

    assert rows(connection, "SELECT * FROM ordinary") == [[1, 7]]
    assert rows(connection, "SELECT * FROM audit") == [[7]]
    close(database, connection)
  end

  test "disabled parser gates and enabled safe switches are deterministic", %{root: root} do
    cases = [
      {:generated_columns,
       "CREATE TABLE generated(a INTEGER, b INTEGER GENERATED ALWAYS AS (a + 1))"},
      {:without_rowid, "CREATE TABLE compact(id INTEGER PRIMARY KEY) WITHOUT ROWID"},
      {:attach, "ATTACH DATABASE '#{tmp_path(root, "attached.db")}' AS attached"},
      {:vacuum, "VACUUM"},
      {:index_method,
       "CREATE TABLE search(body TEXT); CREATE INDEX search_idx ON search USING fts (body)"}
    ]

    for {feature, sql} <- cases do
      {disabled_db, disabled} = open(tmp_path(root, "disabled-#{feature}.db"))
      assert {:error, %Error{code: :misuse}} = Connection.execute_batch(disabled, sql)
      close(disabled_db, disabled)
    end

    {generated_db, generated} =
      open(tmp_path(root, "generated.db"), features: [:generated_columns])

    :ok =
      Connection.execute(
        generated,
        "CREATE TABLE generated(a INTEGER, b INTEGER GENERATED ALWAYS AS (a + 1))"
      )

    :ok = Connection.execute(generated, "INSERT INTO generated(a) VALUES (4)")
    assert rows(generated, "SELECT a, b FROM generated") == [[4, 5]]
    close(generated_db, generated)

    {rowid_db, rowid} = open(tmp_path(root, "rowid.db"), features: [:without_rowid])
    :ok = Connection.execute(rowid, "CREATE TABLE compact(id INTEGER PRIMARY KEY) WITHOUT ROWID")
    close(rowid_db, rowid)

    {attach_db, attach} = open(tmp_path(root, "main.db"), features: [:attach])

    :ok =
      Connection.execute(attach, "ATTACH DATABASE '#{tmp_path(root, "enabled-aux.db")}' AS aux")

    assert Enum.any?(rows(attach, "PRAGMA database_list"), fn [_seq, name, _file] ->
             name == "aux"
           end)

    :ok = Connection.execute(attach, "DETACH DATABASE aux")
    close(attach_db, attach)

    {vacuum_db, vacuum} = open(tmp_path(root, "vacuum.db"), features: [:vacuum])
    :ok = Connection.execute(vacuum, "CREATE TABLE initialized(value INTEGER)")
    :ok = Connection.execute(vacuum, "VACUUM")
    close(vacuum_db, vacuum)
  end

  test "unsupported switches fail validation before native allocation" do
    baseline = Native.resource_snapshot()

    for feature <- [:encryption, :autovacuum, :mvcc_passive_checkpoint, :unknown] do
      assert {:error, %Error{code: :unsupported}} = Database.open(:memory, features: [feature])
    end

    assert baseline == Native.resource_snapshot()
  end

  test "incompatible multiprocess MVCC combination fails before allocation" do
    baseline = Native.resource_snapshot()

    assert {:error, %Error{code: :invalid_argument}} =
             Database.open(:memory,
               journal_mode: :mvcc,
               features: [:multiprocess_wal]
             )

    assert baseline == Native.resource_snapshot()
  end

  test "unsafe enabled type and materialized-view probes run only in child BEAMs", %{root: root} do
    for feature <- ["custom_types", "materialized_views"] do
      result =
        run_probe([
          "experimental-sql",
          feature,
          tmp_path(root, "#{feature}.db")
        ])

      case result do
        {:ok, {output, 0}} -> assert output =~ "result:#{feature}:"
        {:ok, {_output, status}} -> assert status > 0
        :timeout -> flunk("#{feature} probe exceeded its 15 second bound")
      end
    end
  end

  defp run_probe(args) do
    task =
      Task.async(fn ->
        System.cmd(
          "mix",
          ["run", "--no-compile", "bin/capability_probe.exs" | args],
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
