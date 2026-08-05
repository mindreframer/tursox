# Databases and connections

`Tursox.Database.open/2` opens one native Turso database. Every
`Database.connect/2` call invokes that handle's `Database::connect`; it never
reopens a path. Connections derived from one `:memory` database therefore share
state, while separate memory opens are isolated.

File paths are normalized with `Path.expand/1`. Missing parents are rejected by
default; use `create_parent: true` to create them. Turso 0.7.2 does not expose a
stable read-only or read/write-without-create local builder, so those modes
return `:unsupported` instead of being ignored.

```elixir
{:ok, database} = Tursox.Database.open("data/app.db", create_parent: true)
{:ok, first} = Tursox.Database.connect(database, busy_timeout: 2_000)
{:ok, second} = Tursox.Database.connect(database)
```

Database features are explicit through `features: [...]`. The supported names
are returned by `Tursox.Database.builder_features/0`; all are experimental
upstream. Encryption, custom VFS/I/O, cloud sync, and production multiprocess
support are not exposed. `:multiprocess_wal` is rejected with MVCC.

Close is idempotent. Closing a database prevents new connections and invalidates
existing descendants with `%Tursox.Error{code: :closed}`. Descendants retain the
parent native allocation until they close, preventing use-after-free. Close all
connections before or after the parent to return logical counters to baseline.

Pragma helpers validate identifiers and values before constructing engine SQL.
They preserve ordered row lists. They are intended for connection settings and
maintenance, not as a replacement for prepared SQL.
