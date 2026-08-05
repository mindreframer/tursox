{:ok, 1} = Tursox.smoke()
{:ok, database} = Tursox.Database.open(:memory, features: [:index_method])
{:ok, connection} = Tursox.Database.connect(database)
:ok = Tursox.Connection.execute(connection, "CREATE TABLE smoke (value TEXT)")
:ok = Tursox.Connection.execute(connection, "CREATE INDEX smoke_fts ON smoke USING fts(value)")
:ok = Tursox.Connection.execute(connection, "INSERT INTO smoke VALUES (?)", ["precompiled"])

{:ok, cursor} =
  Tursox.Connection.query(connection, "SELECT value FROM smoke WHERE fts_match(value, ?)", [
    "precompiled"
  ])

{:done, [["precompiled"]]} = Tursox.Cursor.fetch(cursor, 10)

{:ok, cursor} =
  Tursox.Connection.query(connection, "SELECT length(uuid4()), regexp('compiled', ?)", [
    "precompiled"
  ])

{:done, [[16, 1]]} = Tursox.Cursor.fetch(cursor, 10)
:ok = Tursox.Connection.close(connection)
:ok = Tursox.Database.close(database)
IO.puts("Precompiled public API smoke passed")
