defmodule Tursox.TypeCapabilityTest do
  use Tursox.TestSupport.TmpCase, async: true

  alias Tursox.{Connection, Cursor, Database, Error, Statement}
  alias Tursox.TestSupport.CapabilityProbe

  setup %{tmp_dir: root}, do: {:ok, root: root}

  test "ordinary affinity remains flexible while STRICT enforces five base types" do
    {database, connection} = open(:memory)

    :ok =
      Connection.execute_batch(connection, """
      CREATE TABLE flexible(i INTEGER, r REAL, t TEXT, b BLOB);
      CREATE TABLE strict_values(
        id INTEGER PRIMARY KEY,
        i INTEGER,
        r REAL,
        t TEXT,
        b BLOB,
        any_value ANY
      ) STRICT;
      """)

    :ok =
      Connection.execute(
        connection,
        "INSERT INTO flexible VALUES (?, ?, ?, ?)",
        ["not-an-integer", "2.5", 7, "text-in-blob"]
      )

    assert rows(connection, "SELECT typeof(i), typeof(r), typeof(t), typeof(b) FROM flexible") ==
             [["text", "real", "text", "text"]]

    {:ok, insert} =
      Connection.prepare(connection, "INSERT INTO strict_values VALUES (?, ?, ?, ?, ?, ?)")

    assert {:ok, _} =
             Statement.execute(insert, [1, "42", 7, 99, {:blob, <<0, 255>>}, "semantic"])

    :ok = Statement.close(insert)

    assert rows(connection, """
           SELECT id, i, r, t, b, any_value,
                  typeof(i), typeof(r), typeof(t), typeof(b), typeof(any_value)
           FROM strict_values
           """) == [
             [
               1,
               42,
               7.0,
               "99",
               {:blob, <<0, 255>>},
               "semantic",
               "integer",
               "real",
               "text",
               "blob",
               "text"
             ]
           ]

    invalid = [
      {"i", "bad"},
      {"r", "bad"},
      {"t", {:blob, <<1>>}},
      {"b", "bad"}
    ]

    for {column, value} <- invalid do
      assert {:error, %Error{}} =
               Connection.execute(
                 connection,
                 "INSERT INTO strict_values(id, #{column}) VALUES (?, ?)",
                 [System.unique_integer([:positive]), value]
               )
    end

    assert rows(connection, "SELECT COUNT(*) FROM strict_values") == [[1]]
    close(database, connection)
  end

  test "STRICT constraints, transaction rollback, indexes, connections, and reopen", %{root: root} do
    path = tmp_path(root)
    {database, writer} = open(path)
    {:ok, reader} = Database.connect(database)

    :ok =
      Connection.execute_batch(writer, """
      CREATE TABLE typed(
        id INTEGER PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        amount INTEGER CHECK(amount >= 0)
      ) STRICT;
      CREATE INDEX typed_amount_idx ON typed(amount);
      """)

    assert {:ok, :inserted} =
             Connection.transaction(writer, fn ->
               :ok = Connection.execute(writer, "INSERT INTO typed VALUES (1, 'ok', 10)")
               :inserted
             end)

    assert rows(reader, "SELECT id, code, amount FROM typed") == [[1, "ok", 10]]

    assert {:error, %Error{}} =
             Connection.transaction(writer, fn ->
               :ok = Connection.execute(writer, "INSERT INTO typed VALUES (2, 'rollback', 20)")
               Connection.execute(writer, "UPDATE typed SET amount = -1 WHERE id = 2")
             end)

    assert rows(reader, "SELECT id, code, amount FROM typed") == [[1, "ok", 10]]
    assert rows(writer, "EXPLAIN QUERY PLAN SELECT id FROM typed WHERE amount = 10") != []

    Connection.close(reader)
    close(database, writer)

    {reopened, connection} = open(path)

    assert rows(connection, "SELECT id, code, amount FROM typed ORDER BY amount") == [
             [1, "ok", 10]
           ]

    assert {:ok, [["ok"]]} = Connection.pragma_query(connection, :integrity_check)
    close(reopened, connection)
  end

  test "0.7.2 type inventory contains only transport base types" do
    {database, connection} = open(:memory)

    assert {:ok,
            [
              ["INTEGER", nil, nil, nil, nil, nil],
              ["REAL", nil, nil, nil, nil, nil],
              ["TEXT", nil, nil, nil, nil, nil],
              ["BLOB", nil, nil, nil, nil, nil],
              ["ANY", nil, nil, nil, nil, nil]
            ]} = Connection.pragma_query(connection, :list_types)

    assert {:error, %Error{}} =
             Connection.query(connection, "SELECT name, sql FROM sqlite_turso_types")

    close(database, connection)
  end

  test "custom types, domains, arrays, STRUCT, and UNION are gated when disabled" do
    {database, connection} = open(:memory)

    sql = [
      "CREATE TYPE cents BASE integer ENCODE value * 100 DECODE value / 100",
      "CREATE DOMAIN positive AS integer CHECK(value > 0)",
      "CREATE TABLE builtin(value date) STRICT",
      "CREATE TABLE array_values(value INTEGER[]) STRICT",
      "CREATE TYPE point AS STRUCT(x INT, y INT)",
      "CREATE TYPE platform AS UNION(one INT, two TEXT)"
    ]

    for statement <- sql do
      assert {:error, %Error{code: :misuse}} = Connection.execute(connection, statement)
    end

    close(database, connection)
  end

  test "enabled custom type families prove an exact child-process memory fault", %{root: root} do
    for kind <- ~w(custom_type builtin array struct union domain) do
      result =
        CapabilityProbe.run([
          "type-sql",
          kind,
          tmp_path(root, "#{kind}.db")
        ])

      assert result.kind == :signal
      assert result.signal in [:sigbus, :sigsegv]
      assert result.status in [135, 138, 139]
      assert result.last_phase == "before_open"
      refute result.output =~ "ArgumentError"
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
