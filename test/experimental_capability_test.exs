defmodule Tursox.ExperimentalCapabilityTest do
  use Tursox.TestSupport.TmpCase, async: true

  alias Tursox.{Capabilities, Connection, Cursor, Database, Error}
  alias Tursox.TestSupport.CapabilityProbe

  setup %{tmp_dir: root}, do: {:ok, root: root}

  test "machine-readable matrix is complete and aligned with builder options" do
    matrix = Capabilities.experimental_features()

    assert Map.keys(matrix) |> Enum.sort() ==
             ~w(attach autovacuum custom_types encryption generated_columns index_method
                materialized_views multiprocess_wal mvcc_passive_checkpoint runtime_extensions
                strict triggers vacuum
                views without_rowid)a
             |> Enum.sort()

    assert Enum.all?(matrix, fn {_name, entry} -> entry.status in Capabilities.statuses() end)

    exposed =
      matrix
      |> Enum.flat_map(fn {_name, entry} -> if entry.option, do: [entry.option], else: [] end)
      |> Enum.sort()

    assert Enum.sort(Database.builder_features()) == exposed

    assert matrix.encryption.builder == :experimental_encryption
    assert matrix.encryption.option == :encryption
    assert matrix.autovacuum.option == :autovacuum
    assert matrix.generated_columns.status == :unsafe
    assert matrix.mvcc_passive_checkpoint.option == :mvcc_passive_checkpoint
    assert matrix.views.option == :views

    assert Enum.sort(Database.unsafe_builder_features()) ==
             ~w(custom_types generated_columns materialized_views mvcc_passive_checkpoint runtime_extensions vacuum views)a
             |> Enum.sort()

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
      {:views, "CREATE MATERIALIZED VIEW materialized AS SELECT 1"},
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
  end

  test "autovacuum's omitted wrapper switch is accessible and its pinned limitation is exact", %{
    root: root
  } do
    path = tmp_path(root, "autovacuum.db")
    {disabled_db, disabled} = open(path)

    assert {:error, %Error{message: message}} =
             Connection.pragma_update(disabled, :auto_vacuum, :full)

    assert message =~ "Autovacuum is not enabled"
    close(disabled_db, disabled)

    {enabled_db, enabled} = open(path, features: [:autovacuum])
    assert {:ok, []} = Connection.pragma_update(enabled, :auto_vacuum, :full)
    # 0.7.2 emits no result metadata and leaves the fresh-file mode at zero.
    assert {:ok, [[]]} = Connection.pragma_query(enabled, :auto_vacuum)
    close(enabled_db, enabled)
  end

  test "unknown switches still fail validation" do
    assert {:error, %Error{code: :unsupported}} = Database.open(:memory, features: [:unknown])
  end

  test "incompatible multiprocess MVCC combination is rejected" do
    assert {:error, %Error{code: :invalid_argument}} =
             Database.open(:memory,
               journal_mode: :mvcc,
               features: [:multiprocess_wal]
             )
  end

  test "unsafe probes distinguish completed behavior from native memory faults", %{root: root} do
    materialized =
      CapabilityProbe.run([
        "experimental-sql",
        "views",
        tmp_path(root, "views.db")
      ])

    assert_memory_fault(materialized, "materialized_views_before_create")

    custom =
      CapabilityProbe.run([
        "experimental-sql",
        "custom_types",
        tmp_path(root, "custom_types.db")
      ])

    assert_memory_fault(custom, "before_open")

    vacuum =
      CapabilityProbe.run([
        "experimental-sql",
        "vacuum",
        tmp_path(root, "vacuum.db")
      ])

    case vacuum.kind do
      :success ->
        assert vacuum.last_phase == "closed"
        assert vacuum.output =~ "result:vacuum::ok"

      :signal ->
        assert_memory_fault(vacuum, "vacuum_before_execute")
    end

    generated =
      CapabilityProbe.run([
        "experimental-sql",
        "generated_columns",
        tmp_path(root, "generated_columns.db")
      ])

    case :os.type() do
      {:unix, :darwin} ->
        assert generated.kind == :success
        assert generated.last_phase == "closed"
        assert generated.output =~ "result:generated_columns:{:ok, [[4, 5]]}"

      _ ->
        assert_memory_fault(generated, generated.last_phase)

        assert generated.last_phase in [
                 "generated_columns_inserted",
                 "generated_columns_queried"
               ]
    end
  end

  test "unsafe passive MVCC checkpoint is selectable and exactly contained", %{root: root} do
    result =
      CapabilityProbe.run([
        "mvcc-manual-checkpoint",
        tmp_path(root, "mvcc-passive.db")
      ])

    assert_memory_fault(result, "mvcc_before_passive_checkpoint")
  end

  defp assert_memory_fault(result, phase) do
    assert result.kind == :signal
    assert result.signal in [:sigbus, :sigsegv]
    assert result.status in [135, 138, 139]
    assert result.last_phase == phase
    refute result.output =~ "ArgumentError"
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
