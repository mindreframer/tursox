defmodule Tursox.FtsTest do
  use Tursox.TestSupport.TmpCase, async: false

  alias Tursox.{Connection, Cursor, Database, Error, Native}

  setup %{tmp_dir: root} do
    baseline = Native.resource_snapshot()
    path = tmp_path(root, "fts.db")
    {:ok, database} = Database.open(path, features: [:index_method])
    {:ok, connection} = Database.connect(database)

    on_exit(fn ->
      Connection.close(connection)
      Database.close(database)
      assert baseline == Native.resource_snapshot()
    end)

    {:ok, root: root, path: path, database: database, connection: connection}
  end

  test "FTS indexes match, rank, highlight, bind, and bound ordered results", %{
    connection: connection
  } do
    seed(connection)

    assert rows(
             connection,
             "SELECT id, title FROM articles " <>
               "WHERE fts_match(title, body, ?) ORDER BY id",
             ["database"]
           ) == [[1, "Introduction to Databases"], [3, "Database Tuning"]]

    ranked =
      rows(connection, """
      SELECT id, fts_score(title, body, 'database') AS score
      FROM articles
      WHERE fts_match(title, body, 'database')
      ORDER BY score DESC
      """)

    assert [[3, high], [1, low]] = ranked
    assert is_float(high) and is_float(low) and high > low

    assert rows(connection, """
           SELECT id, fts_highlight(title, '<b>', '</b>', 'database')
           FROM articles
           WHERE fts_match(title, body, 'database')
           ORDER BY id
           """) == [
             [1, "Introduction to Databases"],
             [3, "<b>Database</b> Tuning"]
           ]

    assert rows(
             connection,
             "SELECT id FROM articles WHERE fts_match(title, body, ?) ORDER BY id",
             ["database AND tuning"]
           ) == [[3]]

    assert rows(connection, """
           SELECT id FROM articles
           WHERE fts_match(title, body, '"full text"') ORDER BY id
           """) == [[2]]

    assert {:ok, cursor} =
             Connection.query(
               connection,
               "SELECT id FROM articles WHERE fts_match(title, body, 'database') ORDER BY id"
             )

    assert {:rows, [[1]]} = Cursor.fetch(cursor, 1)
    assert {:rows, [[3]]} = Cursor.fetch(cursor, 1)
    assert :done = Cursor.fetch(cursor, 1)
  end

  test "global tokenizers and weights create; per-column syntax is unavailable", %{
    connection: connection
  } do
    for {suffix, tokenizer} <- [
          {"raw", "raw"},
          {"simple", "simple"},
          {"space", "whitespace"},
          {"ngram", "ngram"}
        ] do
      :ok = Connection.execute(connection, "CREATE TABLE docs_#{suffix}(body TEXT)")

      assert :ok =
               Connection.execute(
                 connection,
                 "CREATE INDEX docs_#{suffix}_idx ON docs_#{suffix} USING fts (body) " <>
                   "WITH (tokenizer = '#{tokenizer}')"
               )
    end

    :ok = Connection.execute(connection, "CREATE TABLE weighted(title TEXT, body TEXT)")

    assert :ok =
             Connection.execute(
               connection,
               "CREATE INDEX weighted_idx ON weighted USING fts (title, body) " <>
                 "WITH (weights = 'title=2.0,body=1.0')"
             )

    :ok = Connection.execute(connection, "CREATE TABLE per_column(body TEXT)")

    assert {:error, %Error{code: :misuse}} =
             Connection.execute(
               connection,
               "CREATE INDEX unavailable ON per_column USING fts " <>
                 "(body WITH tokenizer=simple)"
             )
  end

  test "FTS index follows insert, update, delete, rollback, optimize, drop, and reopen", %{
    connection: connection,
    database: database,
    path: path
  } do
    :ok =
      Connection.execute_batch(
        connection,
        "CREATE TABLE lifecycle(id INTEGER PRIMARY KEY, body TEXT); " <>
          "CREATE INDEX lifecycle_fts ON lifecycle USING fts(body)"
      )

    :ok = Connection.begin(connection)
    :ok = Connection.execute(connection, "INSERT INTO lifecycle VALUES (1, 'alpha')")
    # 0.7.2 differs from newer docs: the writing connection reads its FTS write.
    assert rows(connection, "SELECT id FROM lifecycle WHERE fts_match(body, 'alpha')") == [[1]]
    :ok = Connection.rollback(connection)
    assert rows(connection, "SELECT id FROM lifecycle WHERE fts_match(body, 'alpha')") == []

    :ok = Connection.execute(connection, "INSERT INTO lifecycle VALUES (1, 'alpha')")
    :ok = Connection.execute(connection, "UPDATE lifecycle SET body = 'beta' WHERE id = 1")
    assert rows(connection, "SELECT id FROM lifecycle WHERE fts_match(body, 'alpha')") == []
    assert rows(connection, "SELECT id FROM lifecycle WHERE fts_match(body, 'beta')") == [[1]]
    :ok = Connection.execute(connection, "OPTIMIZE INDEX lifecycle_fts")

    Connection.close(connection)
    Database.close(database)
    {:ok, reopened} = Database.open(path, features: [:index_method])
    {:ok, reopened_connection} = Database.connect(reopened)

    assert rows(reopened_connection, "SELECT id FROM lifecycle WHERE fts_match(body, 'beta')") ==
             [[1]]

    :ok = Connection.execute(reopened_connection, "DELETE FROM lifecycle WHERE id = 1")

    assert rows(reopened_connection, "SELECT id FROM lifecycle WHERE fts_match(body, 'beta')") ==
             []

    :ok = Connection.execute(reopened_connection, "DROP INDEX lifecycle_fts")

    assert rows(
             reopened_connection,
             "SELECT name FROM sqlite_schema WHERE name = 'lifecycle_fts'"
           ) == []

    # The scalar matcher remains available as a scan after the index is dropped.
    assert rows(reopened_connection, "SELECT id FROM lifecycle WHERE fts_match(body, 'beta')") ==
             []

    Connection.close(reopened_connection)
    Database.close(reopened)
  end

  test "invalid index and query inputs fail safely", %{connection: connection} do
    seed(connection)

    assert {:error, %Error{}} =
             Connection.execute(
               connection,
               "CREATE INDEX bad_method ON articles USING unknown_method(title)"
             )

    assert {:error, %Error{}} =
             all_rows(connection, """
             SELECT id FROM articles WHERE fts_match(title, body, '(')
             """)

    assert {:error, %Error{}} = all_rows(connection, "SELECT fts_match('only one argument')")
  end

  defp seed(connection) do
    :ok =
      Connection.execute_batch(connection, """
      CREATE TABLE articles(id INTEGER PRIMARY KEY, title TEXT, body TEXT);
      CREATE INDEX articles_fts ON articles USING fts(title, body)
        WITH (weights = 'title=2.0,body=1.0');
      INSERT INTO articles VALUES
        (1, 'Introduction to Databases', 'database efficient retrieval'),
        (2, 'Full Text Search', 'finding documents by content'),
        (3, 'Database Tuning', 'optimizing database indexes'),
        (4, 'Rust', 'systems programming language');
      """)
  end

  defp rows(connection, sql, params \\ []) do
    {:ok, values} = all_rows(connection, sql, params)
    values
  end

  defp all_rows(connection, sql, params \\ []) do
    with {:ok, cursor} <- Connection.query(connection, sql, params),
         {:ok, result} <- Cursor.all(cursor, 10_000, 64) do
      {:ok, result.rows}
    end
  end
end
