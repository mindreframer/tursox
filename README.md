# Tursox

[![Hex.pm](https://img.shields.io/hexpm/v/tursox.svg)](https://hex.pm/packages/tursox)
[![HexDocs](https://img.shields.io/badge/HexDocs-API%20reference-6e4a7e.svg)](https://hexdocs.pm/tursox)
[![CI](https://github.com/mindreframer/tursox/actions/workflows/ci.yml/badge.svg)](https://github.com/mindreframer/tursox/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/mindreframer/tursox/blob/main/LICENSE)

Tursox is an Elixir wrapper around the embedded
[Turso](https://github.com/tursodatabase/turso) engine. It preserves Turso's
ownership model: one database derives independent connections, real prepared
statements, and bounded row cursors. Optional shared-handle DBConnection pools
and caller-supervised multi-database managers build on the same resources.
There is no global registry.

Version 0.2.1 pins Turso 0.7.2 and Rust 1.91.0. It deliberately enables tested
Turso FTS while MVCC and advanced builder features remain explicit experimental
opt-ins. See the [Roadmap 2 capability report](docs/roadmap002-capabilities.md),
[capability matrix](docs/capabilities.md), and
[compatibility notes](docs/compatibility/turso-0.7.2.md).

## Installation

After release, add:

```elixir
def deps, do: [{:tursox, "~> 0.2.1"}]
```

Supported targets use NIF 2.16 precompiled binaries after their published
checksums are committed. Set `TURSOX_BUILD=1` to force a source build with the
pinned Rust toolchain. A missing or invalid precompiled artifact fails loudly;
it never silently falls back to an unverified binary.

## Direct resources

```elixir
{:ok, database} = Tursox.Database.open("data/app.db", journal_mode: :wal)
{:ok, connection} = Tursox.Database.connect(database, busy_timeout: 5_000)
:ok = Tursox.Connection.execute(connection, "CREATE TABLE IF NOT EXISTS users (id INTEGER, name TEXT)")
{:ok, statement} = Tursox.Connection.prepare(connection, "INSERT INTO users VALUES (?, ?)")
{:ok, _result} = Tursox.Statement.execute(statement, [1, "Ada"])
{:ok, cursor} = Tursox.Connection.query(connection, "SELECT id, name FROM users ORDER BY id")
{:done, rows} = Tursox.Cursor.fetch(cursor, 100)
:ok = Tursox.Connection.close(connection)
:ok = Tursox.Database.close(database)
```

Rows are ordered lists. Parameters are strict positional lists or named maps;
use `{:blob, binary}` for BLOBs. Fetches are bounded to 10,000 rows. For details,
see [databases and connections](docs/databases-and-connections.md),
[queries and cursors](docs/queries-and-cursors.md), and
[transactions and MVCC](docs/transactions-and-mvcc.md).

Tursox 0.2.1 verifies core SQL, safe argument-bearing PRAGMAs, STRICT and
advanced schema behavior, Tantivy-backed FTS, built-in extensions, and
platform-limited multiprocess WAL. Unsupported and unsafe pinned-engine results
are published with executable evidence. Enable ordinary experimental switches
at database open; no consumer recompilation is required:

```elixir
{:ok, db} =
  Tursox.Database.open("app.db",
    features: [:index_method, :autovacuum, :attach, :without_rowid]
  )
```

> **DANGER:** `unsafe_features` exposes pinned engine paths that may terminate
> the entire BEAM. They are intentionally available for cutting-edge use:
>
> ```elixir
> Tursox.Database.open("edge.db",
>   journal_mode: :mvcc,
>   unsafe_features: [:views, :custom_types, :generated_columns,
>                     :vacuum, :mvcc_passive_checkpoint, :runtime_extensions]
> )
> ```

Encryption is compiled into every build and accepts raw 16/32-byte keys via
`features: [:encryption], encryption: [cipher: ..., key: ...]`. Runtime native
libraries load with `Tursox.Connection.load_extension/2`; they must implement
Turso's extension ABI. SQLite-only binaries such as SQLean 0.28.3 do not.

## Pool and manager

```elixir
{:ok, pool} = Tursox.Pool.start_link(database: "data/app.db", pool_size: 4)
{:ok, result} = Tursox.Pool.execute(pool, "UPDATE users SET name = ? WHERE id = ?", ["Grace", 1])

{:ok, manager} = Tursox.Manager.start_link(max_databases: 100)
{:ok, tenant_pool} = Tursox.Manager.open(manager, tenant_id, "data/tenant.db", pool_size: 4)
```

One pool owns one database and derives N workers from that shared handle. A
manager atomically enforces tenant IDs, canonical paths, and capacity without
creating dynamic atoms. See [pools](docs/pools.md) and
[managers](docs/managers.md).

## Runtime and observability

Native work runs on dirty schedulers through one process-lifetime Tokio runtime.
Resource close is logical, idempotent, ancestry-aware, and inspect-safe.
Telemetry events under `[:tursox, ...]` include durations and result classes but
never SQL, parameters, rows, tokens, or database contents. `Tursox.resources/0`
returns logical native resource gauges.

## Development

```sh
bin/qa_check.sh
```

No sibling checkout or network service is required for normal QA. Precompiled
release publication is a separate manual workflow and is never implied by a
source commit.

## License

MIT. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.
