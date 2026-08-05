# ROADMAP001 — Tursox: Flexible Embedded Turso Foundations

- **Status:** Planned
- **Target:** `0.1.0`
- **Primary interface:** Elixir
- **Native implementation:** Rust via Rustler
- **Engine baseline:** `turso = 0.7.2` (exact stable pin; verify before Epic 1 closes)

## 1. Goal

Build Tursox as a low-level, flexible Elixir wrapper around Turso Database for applications that keep many independent embedded databases open at once.

The first release must preserve Turso's real resource model: one database handle can create multiple independent connections, and each connection can own prepared statements and incremental row cursors. The library must expose that model directly, then provide optional `DBConnection` and supervised multi-database layers without making either one mandatory.

MVCC is a first-class capability. Applications must be able to select `journal_mode: :mvcc`, use `BEGIN CONCURRENT`, distinguish retryable snapshot conflicts, tune supported checkpoint behavior, and verify concurrent write behavior through tests.

## 2. Research Baseline

The roadmap was prepared against these local references on 2026-08-05:

- Turso source at revision `2bdeb831796f62b4ff2f8393f93ddc1a17ebba50` (`0.8.0-pre.2` on `main`).
- Latest stable crates.io release `turso 0.7.2`; prerelease `0.8.0-pre.2` is not the initial release baseline.
- `ex_turso` in Concord at revision `9400a1fc49e4a06511f4fcbfb62a3d17c50f6c02`.
- Exqlite at revision `f92573ba188a4794ddc70e9a76c7e375d579f6a9` for familiar low-level Elixir SQLite conventions.
- Parquex as the structural reference for Rustler, exact dependency pins, QA, packaging, precompiled NIFs, and release verification.

Epic 1 must record the exact Turso source/API observations that apply to the selected stable crate. Behavior found only on Turso `main` must not be advertised unless the dependency is deliberately changed and pinned.

## 3. Key Direction

### Adopt from `ex_turso`

- Rustler `ResourceArc` ownership for native handles.
- Coarse native-to-Elixir error translation as a starting point.
- Dirty-scheduler protection around blocking native entry points.
- `DBConnection` protocol knowledge and result structs.
- Explicit local database and cloud-sync separation.

### Correct or replace from `ex_turso`

- Do not open a new `turso::Database` for every pooled connection. Open one database and derive many connections from it.
- Do not collect an entire result set in one NIF call. Keep a native cursor and fetch bounded row chunks.
- Do not silently turn ordered rows into maps; duplicate column names and column order must be preserved. Map conversion is explicit.
- Do not fake preparation as a no-op. Prepared statement and cursor resources must map to the Rust API.
- Do not force source builds after precompiled artifacts exist.
- Do not unconditionally enable one experimental builder feature.
- Do not collapse `BusySnapshot` into generic `:busy`; MVCC retry policy needs the distinction.
- Do not make `DBConnection` the only way to use the library.

### Adopt from Exqlite

- Familiar `open`, `prepare`, `bind/query`, `step/fetch`, `reset`, and explicit close/release concepts where Turso supports them.
- Ordered row lists and explicit `{:blob, binary}` parameters.
- Configurable chunk sizes, busy timeout, transaction modes, and pragma helpers.
- A low-level API separate from the pooled adapter.

Tursox will not claim drop-in Exqlite compatibility. Its database/connection split is intentional and reflects Turso's model.

## 4. In Scope

- A reproducible Elixir/Rustler project and authoritative QA gate.
- Exact, stable dependency and Rust toolchain pins.
- Local file and in-memory Turso databases.
- Explicit database, connection, statement, and cursor resources.
- Positional and named bound parameters for SQLite values.
- Bounded incremental row fetching and explicit result conversion helpers.
- Execute, execute-batch, prepare, query, pragma, connection status, changes, last row ID, cache flush, and busy timeout where supported by the pinned crate.
- Deferred, immediate, exclusive, and concurrent transactions.
- MVCC journal selection, conflict classification, retry helpers, and checkpoint controls supported by the pinned engine.
- A `DBConnection` adapter that shares one database handle across pool connections.
- A supervised, non-global manager for many independently configured databases.
- Resource lifecycle tests, multi-database isolation tests, telemetry, documentation, and precompiled NIF release automation.

## 5. Explicitly Deferred

- Ecto adapter implementation. The `DBConnection` layer should make a later adapter possible.
- A network protocol, HTTP server, PostgreSQL frontend, authentication, authorization, tenant routing policy, or rate limiting.
- Turso Cloud sync and serverless remote access.
- Cross-process access and multiprocess WAL as a supported production mode.
- Automatic schema migrations.
- Automatic idle eviction, persistence catalogs, quotas, or billing policy beyond explicit capacity limits.
- User-defined Rust/Elixir SQL functions, collations, VFS implementations, and loadable native extensions.
- Backup, serialize/deserialize, incremental BLOB I/O, and SQLite C-API parity not exposed by the stable Rust API.
- Transparent Date/Time encoding and an extensible type-conversion framework.
- Guaranteed interruption of an already-running Turso Rust future unless the pinned public Rust API supports it. Timeouts and cancellation limitations must be documented honestly.
- Production-readiness claims for Turso features that upstream marks experimental, including MVCC.

## 6. Public Architecture

```text
Direct API (always available)
Tursox.Database
    └── Tursox.Connection
          ├── Tursox.Statement
          └── Tursox.Cursor (bounded fetch)

Optional managed API
Tursox.Manager
    └── one supervised entry per tenant/database
          └── Tursox.Pool (DBConnection)
                └── connections derived from one Database resource
```

Expected direct API shape:

```elixir
{:ok, db} = Tursox.Database.open("tenant-a.db", journal_mode: :mvcc)
{:ok, conn} = Tursox.Database.connect(db, busy_timeout: 2_000)

:ok = Tursox.Connection.execute(conn, "CREATE TABLE items (id INTEGER PRIMARY KEY, value TEXT)")
{:ok, stmt} = Tursox.Connection.prepare(conn, "SELECT id, value FROM items WHERE id > ?")
{:ok, cursor} = Tursox.Statement.query(stmt, [0])
{:rows, rows} = Tursox.Cursor.fetch(cursor, 100)
:done = Tursox.Cursor.fetch(cursor, 100)
```

Names may be refined before Epic 2 closes, but the resource hierarchy and bounded cursor contract are architectural constraints.

## 7. Core Invariants

1. **One database, many connections:** every pool or managed database opens one native database resource and derives connections from it.
2. **No process-global database registry:** callers may run multiple managers with isolated names and policies.
3. **Per-database configuration:** journal mode, builder features, pragmas, limits, and pool settings do not leak between tenants.
4. **Bounded result transfer:** query memory is a function of fetch size and row size, not total result cardinality, unless the caller explicitly requests `all`.
5. **Ordered results:** native column order and duplicate column names are preserved.
6. **Explicit ownership:** closing a parent prevents new child operations; descendants fail safely with stable closed-resource errors.
7. **Connection isolation:** a connection is a sequential state machine. Managed checkouts prevent transaction interleaving on one connection.
8. **Rollback by default:** failures, throws, exits, and abandoned managed transactions must not commit.
9. **MVCC conflicts are visible:** `BusySnapshot` and other retryable busy outcomes remain programmatically distinguishable.
10. **No normal-scheduler blocking:** database I/O and potentially long native work use the selected managed runtime/dirty scheduling policy.
11. **No hidden secrets or row values:** errors, logs, inspections, and telemetry exclude bound parameter values and row contents.
12. **Stable API over unstable engine details:** unsupported upstream capabilities return documented errors; Turso internals do not leak into public structs.

## 8. Native Runtime Direction

Epic 1 must validate the exact Rustler/Turso combination before locking the implementation, but the intended model is:

- A single lazily initialized multi-threaded Tokio runtime for Turso async futures, with deterministic initialization failure handling.
- Rustler resources containing logical close state and the Turso handle.
- Short, bounded native calls. Cursor fetch performs at most the requested row count per call.
- Dirty scheduling for calls that may block while driving Turso I/O; no ordinary NIF performs unbounded work.
- Mutexes only around a resource's mutable state, never a process-global database operation lock.
- Panic containment at every NIF boundary and stable error conversion.
- Native resource counters available in tests to prove deterministic cleanup without timing sleeps.

If a better Rustler async pattern is proven reliable in Epic 1, it may replace dirty calls, but the public API and lifecycle invariants remain unchanged.

## 9. Error Contract

`Tursox.Error` should carry stable fields such as `:code`, `:message`, `:operation`, and optional safe metadata. Initial codes should distinguish at least:

- `:busy`
- `:busy_snapshot`
- `:constraint`
- `:readonly`
- `:database_full`
- `:interrupt`
- `:io`
- `:corrupt`
- `:misuse`
- `:conversion`
- `:invalid_argument`
- `:closed`
- `:unsupported`
- `:internal`

A helper may classify retryability, but automatic retry is opt-in and limited to transaction boundaries. SQL text may be attached only when explicitly safe; parameter and row values are never attached.

## 10. MVCC Contract

- `journal_mode: :mvcc` is explicit and verified after open.
- `mode: :concurrent` emits `BEGIN CONCURRENT` and is rejected with a clear error if MVCC is not active.
- Retry helpers retry the entire callback, never only `COMMIT`, and use bounded attempts/backoff.
- A conflict test must prove two separate connections can hold write transactions concurrently.
- A same-row conflict test must prove the losing transaction is rolled back and classified as retryable.
- Snapshot-isolation behavior must be tested against the pinned engine.
- Supported `mvcc_checkpoint_threshold`, passive checkpoint builder configuration, and `wal_checkpoint` operations are exposed only after source and runtime verification.
- Documentation must retain upstream's experimental warning and compatibility caveats.

## 11. Quality Policy

`bin/qa_check.sh` is the single repository quality entry point. By the end of Epic 1 it must cover:

- locked dependency verification;
- Elixir format and compilation with warnings as errors;
- ExUnit tests;
- Rust format, `cargo check`, Clippy with warnings denied, and Rust tests;
- deterministic source-build NIF loading;
- generated documentation checks when docs are introduced.

Later epics extend this gate with lifecycle, MVCC, concurrency, stress, package, and precompiled-consumer checks. Tests must use unique temporary directories and must not depend on the sibling Turso, Concord, Exqlite, or Parquex checkouts.

At the end of every epic:

1. Run `bin/qa_check.sh` from the repository root.
2. Fix every failure.
3. Confirm all phase and epic acceptance criteria.
4. Review the diff for generated files, secrets, credentials, and unrelated changes.
5. Check phase boxes only after verification.
6. Commit as `roadmap001 - epic N - <outcome>` with an informative body.

## 12. Epics

### Epic 1 — Native Foundation and Reproducible QA

Establish the Rustler crate, exact dependency baseline, runtime rules, stable error boundary, test foundations, and authoritative QA command.

### Epic 2 — Database and Connection Resources

Implement local/in-memory database opening, advanced validated builder options, one-database/many-connections semantics, explicit close behavior, and per-connection settings.

### Epic 3 — Prepared Statements and Bounded Row Cursors

Implement SQLite-like values and parameters, real prepared statements, ordered metadata, execute paths, and bounded cursor fetching without forced full-result materialization.

### Epic 4 — Transactions and MVCC

Implement transaction modes and rollback safety, make MVCC a tested first-class option, classify snapshot conflicts, and expose bounded whole-transaction retries and checkpoint controls.

### Epic 5 — Shared-Handle `DBConnection` Pool

Build a `DBConnection` adapter whose workers derive connections from one existing database resource, with prepared queries, cursor streaming, checkout isolation, and transaction modes.

### Epic 6 — Supervised Multi-Database Management

Build an optional manager that supervises many isolated database/pool entries, supports explicit open/lookup/list/close, enforces capacity, and avoids a mandatory global registry.

### Epic 7 — Hardening, Documentation, and Initial Release

Add observability, stress and lifecycle coverage, compatibility documentation, precompiled NIF automation, package audits, and release `0.1.0`.

## 13. Dependency Order

```text
Epic 1: native foundation + QA
   ↓
Epic 2: database + connection resources
   ↓
Epic 3: statements + bounded cursors
   ↓
Epic 4: transactions + MVCC
   ↓
Epic 5: shared-handle DBConnection pool
   ↓
Epic 6: supervised multi-database manager
   ↓
Epic 7: hardening + precompiled release
```

## 14. Definition of Initial Success

Tursox `0.1.0` is successful when an Elixir application can:

- open many independently configured local Turso databases in one BEAM instance;
- derive multiple connections from each single database resource;
- execute bound SQL and incrementally consume large results in bounded chunks;
- use prepared statements and ordered row data without losing duplicate columns;
- run deferred, immediate, exclusive, and MVCC concurrent transactions safely;
- detect and retry complete transactions after MVCC conflicts;
- use either direct resources, a shared-handle `DBConnection` pool, or a supervised multi-database manager;
- close and restart managed databases without leaked native resources;
- install from precompiled NIF artifacts on the supported target matrix; and
- understand from the documentation exactly which SQLite and Turso capabilities remain unsupported or experimental.
