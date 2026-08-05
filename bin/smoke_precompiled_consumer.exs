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

path = Path.join(System.tmp_dir!(), "tursox-consumer-encrypted-#{System.unique_integer([:positive])}.db")
key = :binary.copy(<<0x5A>>, 32)
opts = [features: [:encryption], encryption: [cipher: :aes_256_gcm, key: key]]
{:ok, encrypted} = Tursox.Database.open(path, opts)
{:ok, writer} = Tursox.Database.connect(encrypted)
:ok = Tursox.Connection.execute(writer, "CREATE TABLE secret(value TEXT)")
:ok = Tursox.Connection.execute(writer, "INSERT INTO secret VALUES ('ciphertext')")
:ok = Tursox.Connection.close(writer)
:ok = Tursox.Database.close(encrypted)
{:ok, reopened} = Tursox.Database.open(path, opts)
{:ok, reader} = Tursox.Database.connect(reopened)
{:ok, cursor} = Tursox.Connection.query(reader, "SELECT value FROM secret")
{:done, [["ciphertext"]]} = Tursox.Cursor.fetch(cursor, 10)
:ok = Tursox.Connection.close(reader)
:ok = Tursox.Database.close(reopened)
File.rm(path)
File.rm(path <> "-wal")
File.rm(path <> "-shm")

IO.puts("Precompiled public API smoke passed")
