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

Database features are explicit through `features: [...]`; all eleven flags on
Turso's experimental-features page are selectable. Known process-killing paths
use `unsafe_features: [...]` and are returned by
`Tursox.Database.unsafe_builder_features/0`. The old 0.2.x unsafe names in
`:features` remain accepted for compatibility. `:multiprocess_wal` is rejected
with MVCC.

```elixir
{:ok, encrypted} =
  Tursox.Database.open("data/secret.db",
    features: [:encryption],
    encryption: [cipher: :aes_256_gcm, key: <<key::binary-size(32)>>]
  )

{:ok, edge} =
  Tursox.Database.open("data/edge.db",
    unsafe_features: [:views, :custom_types, :generated_columns, :runtime_extensions]
  )
```

Encryption keys are raw 16/32-byte binaries and never enter metadata, inspect,
telemetry, or reports. Runtime extensions execute native code inside the BEAM
and must implement Turso's extension ABI. Custom VFS/I/O and cloud sync remain
unexposed.

Close is idempotent. Closing a database prevents new connections and invalidates
existing descendants with `%Tursox.Error{code: :closed}`. Descendants retain the
parent native allocation until they close, preventing use-after-free. Close all
connections before or after the parent to return logical counters to baseline.

Pragma helpers validate identifiers and values before constructing engine SQL.
They preserve ordered row lists. They are intended for connection settings and
maintenance, not as a replacement for prepared SQL.
