# Turso 0.7.2 native capability record

Verified 2026-08-05 against the published crate source recorded as upstream
commit `046e9cbf67d22491e8ecc941ec2891b02a9f3cad` and the lockfile generated for
Tursox. The published `turso-0.7.2` crate checksum is
`f9491d7a80312c5abe66a4409e4dce02065503a235453c94b9e4133877e39ffc`.

Exact sources:

* [crate](https://crates.io/crates/turso/0.7.2)
* [API](https://docs.rs/turso/0.7.2/turso/)
* [source](https://docs.rs/crate/turso/0.7.2/source/)
* [upstream tag](https://github.com/tursodatabase/turso/tree/v0.7.2)

## Resolution and features

| Component | Exact resolution |
|---|---|
| `turso` | 0.7.2 |
| `turso_core` | 0.7.2 (transitive) |
| `turso_sdk_kit` | 0.7.2 (transitive) |
| `turso_sync_sdk_kit` | 0.7.2 (transitive, not exposed) |
| Tokio | 1.47.1, `rt-multi-thread` |
| Rustler | 0.38.0, NIF 2.16 |
| RustlerPrecompiled | 0.8.4 |
| Rust | 1.91.0 (`f8297e351`) |

`turso` uses `default-features = false`. Tursox therefore does not install the
crate's mimalloc global allocator and does not silently enable FTS. Cloud sync,
pure-Rust crypto, memory-yield, stacker, and test-helper features are disabled.
The production NIF currently uses no Turso API until Epic 2; its exact dependency
is compiled and linted in the Epic 1 gate.

RustlerPrecompiled names these candidate targets: macOS aarch64/x86-64, Linux
aarch64/x86-64 GNU and musl, and Windows x86-64 MSVC. Epic 1 CI proves source
compilation on Linux x86-64; aarch64 Apple is the development host. A target is
not advertised as release-supported until Epic 7 builds and smokes it.

## Stable source surface selected for Tursox

Epic 2 may expose these opt-in `Builder` switches, all present in 0.7.2:
`experimental_attach`, `experimental_custom_types`,
`experimental_generated_columns`, `experimental_index_method`,
`experimental_materialized_views`, `experimental_vacuum`,
`experimental_multiprocess_wal`, `experimental_without_rowid`, and
`experimental_mvcc_passive_checkpoint`. All except passive MVCC checkpointing
are exposed as explicit atoms in `Tursox.Database`'s `:features` option and
covered by lifecycle tests. The passive switch is rejected because executable
0.7.2 probes found its manual checkpoint path unsafe for the VM. Encryption
requires a separate validated key contract and remains unsupported
until implemented. `experimental_triggers` and `experimental_strict` are
compatibility no-ops because those features are always enabled.

Selected stable APIs are:

* `Builder::new_local`, selected feature methods, `Builder::build`, and
  `Database::connect` — used by Epic 2;
* connection pragma query/update, cache flush, autocommit, and busy timeout —
  used by Epic 2;
* connection execute, batch, prepare, and last-insert-rowid — used by Epic 3;
* real `Statement::query`, `execute`, columns, reset, and affected changes —
  used by Epic 3;
* incremental `Rows::next` and ordered row/column access — used by Epic 3;
* none, positional, and prefixed named `IntoParams` values — used by Epic 3;
* `Null`, signed 64-bit `Integer`, `Real`, UTF-8 `Text`, and byte `Blob` — used
  by Epic 3;
* distinct busy, busy-snapshot, interrupt, constraint, readonly, database-full,
  misuse, corrupt/not-a-database, I/O, conversion, and general errors.

Every item is marked used only when its implementation and executable tests land
in the matching epic. This avoids claiming behavior from source inspection alone.

## Transactions and MVCC

Stable `TransactionBehavior` contains deferred, immediate, and exclusive only.
Concurrent mode must execute tested `BEGIN CONCURRENT` SQL; Tursox must not refer
to the `Concurrent` variant added after 0.7.2. `PRAGMA journal_mode = mvcc` must
be set and read back before concurrent mode is accepted.

The source exposes `experimental_mvcc_passive_checkpoint`, but a 0.7.2 runtime
probe of `PRAGMA wal_checkpoint(PASSIVE)` with that switch caused a native bus
error. Tursox therefore rejects the switch and manual MVCC checkpoint calls as
`:unsupported`. `mvcc_checkpoint_threshold` accepts and reads back non-negative
integers; the suite verifies 64. WAL `wal_checkpoint(PASSIVE)` safely returns one
ordered three-integer row (`busy`, log frames, checkpointed frames). MVCC remains
experimental and provides snapshot isolation, not a serializability guarantee.

## Intentionally absent

The stable high-level connection has no public interrupt/query-timeout handle,
no documented total-changes accessor, and no read-only/open-mode builder. Tursox
does not reach into `turso_core` to synthesize those APIs. Cloud sync, remote
access, custom I/O/VFS, and production multiprocess support are deferred.

## Proof

Epic 1 proves exact lock resolution, source compilation, Rust formatting,
`cargo check`, Clippy with denied warnings, Rust tests, source-built NIF loading,
stable error translation, panic containment, and deterministic resource
accounting through `bin/qa_check.sh`. Database, SQL, parameter, cursor, and MVCC
claims require the executable suites added in Epics 2–4.
