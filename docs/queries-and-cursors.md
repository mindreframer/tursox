# Queries, statements, and bounded cursors

Tursox maps to Turso's real prepared statement and incremental `Rows` types.
Rows and column metadata remain ordered; duplicate names are not discarded.

```elixir
:ok = Tursox.Connection.execute(conn, "CREATE TABLE items (id INTEGER, value TEXT)")
{:ok, statement} = Tursox.Connection.prepare(conn, "SELECT id, value FROM items WHERE id > ?")
{:ok, cursor} = Tursox.Statement.query(statement, [0])
{:rows, rows} = Tursox.Cursor.fetch(cursor, 100)
:done = Tursox.Cursor.fetch(cursor, 100)
```

Values are `nil`, signed 64-bit integers, floats, UTF-8 strings, and explicit
`{:blob, binary}` tuples. Booleans bind as integer 1/0. Arbitrary binary data is
never guessed to be text or blob. Named parameter keys may include `:`, `@`,
`$`, or numbered `?` prefixes; unprefixed atom/string names receive `:`.

Only one cursor may lease a prepared statement. Complete, close, or halt that
cursor before resetting or executing the statement again. `Cursor.fetch/2`
returns at most its requested size. `Cursor.stream/2` closes on early halt, and
the cursor itself implements `Enumerable` with bounded chunks.

There is no unbounded `all/1`. `Cursor.all/3` requires an explicit total row
limit and fails once another row proves that limit would be exceeded.

Map conversion is explicit through `Tursox.Result.to_maps/2`; duplicate names
require a `:first` or `:last` collision policy. The default `:error` prevents
silent data loss.
