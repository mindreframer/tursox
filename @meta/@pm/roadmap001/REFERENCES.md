# ROADMAP001 Reference Guide

## 1. Purpose and Required Use

This file makes ROADMAP001 executable without relying on the original planner's memory or filesystem layout.

Every implementation agent must read, in this order:

1. repository-root `AGENTS.md`;
2. `@meta/@pm/ROADMAP001.md`;
3. this file;
4. all seven `EPIC###-spec.md` and `EPIC###-plan.md` files; and
5. the exact pinned dependency source relevant to the current phase.

Local sibling checkouts are read-only research conveniences. They must never become build, test, package, or runtime dependencies. If a local path is absent, use the canonical repository URL and exact revision below. If both local and remote references are unavailable, the findings encoded in section 4 are sufficient to begin Epic 1, but every dependency-facing claim must still be compiled and tested before its phase is checked.

## 2. Source Authority and Conflict Rules

Use this precedence when sources disagree:

1. **Tursox roadmap contracts and accepted ADRs** define what Tursox intends to expose.
2. **The exact crate source in `Cargo.lock`** defines what can be implemented against the selected dependency.
3. **Exact-version docs.rs pages** explain that crate API, but source and compiling tests win over generated prose.
4. **Turso's tagged source and compatibility docs** define engine behavior for that release.
5. **Turso `main`** is forward-looking context only. It must not justify an API when the pinned stable crate lacks it.
6. **`ex_turso`, Exqlite, and Parquex** are design references only, never behavioral authorities for Tursox.

Do not use an unversioned `/latest/` documentation URL to close acceptance criteria. Record the exact version, lockfile resolution, and any relevant upstream revision in the Epic 1 capability matrix.

## 3. Reference Catalog

### R0 — Tursox repository itself

- Repository root means the directory containing this roadmap, `mix.exs`, `lib/`, `test/`, and `bin/qa_check.sh`.
- Local path on the planning machine: `/Users/roman/Desktop/work/prj.ideas/S3MUX/TOOLS_TURSO/tursox`.
- Never hardcode that absolute path in code or scripts; resolve paths from the repository root.
- Initial scaffold commit: `5067d10`; repository instructions: `fdf5377`; roadmap baseline before this clarification: `a75864c`.

Before editing, inspect `mix.exs`, `.formatter.exs`, `.gitignore`, `bin/qa_check.sh`, `lib/`, `test/`, and current `git status`. Repository-root `AGENTS.md` is the execution contract.

### R1 — Turso stable crate: implementation authority

- Package: `turso`
- Initial candidate pin: `=0.7.2`
- Published crate SHA-256: `f9491d7a80312c5abe66a4409e4dce02065503a235453c94b9e4133877e39ffc`
- Source commit recorded by the published crate: `046e9cbf67d22491e8ecc941ec2891b02a9f3cad` (the dereferenced `v0.7.2` tag)
- Crates.io: <https://crates.io/crates/turso/0.7.2>
- Exact API docs: <https://docs.rs/turso/0.7.2/turso/>
- Exact source browser: <https://docs.rs/crate/turso/0.7.2/source/>
- Upstream repository: <https://github.com/tursodatabase/turso>
- Upstream tag: <https://github.com/tursodatabase/turso/tree/v0.7.2>
- Local Cargo cache when already downloaded: `~/.cargo/registry/src/*/turso-0.7.2/`

Retrieve and inspect reproducibly:

```sh
cargo info turso@0.7.2
find "${CARGO_HOME:-$HOME/.cargo}/registry/src" -maxdepth 3 -type d -name 'turso-0.7.2'
```

Important files inside the crate:

- `Cargo.toml` — features and dependency surface.
- `src/lib.rs` — `Builder`, `Database`, `Statement`, `Error`, and exports.
- `src/connection.rs` — query, execute, batch, prepare, pragma, cache, status, and timeout APIs.
- `src/transaction.rs` — transaction lifetime/drop behavior and supported enum variants.
- `src/rows.rs` — incremental `Rows::next` and row metadata.
- `src/params.rs` — positional/named parameter conversion.
- `src/value.rs` — five SQLite value classes.

Epic 1 must pin the crate exactly in `native/tursox_nif/Cargo.toml`, commit `Cargo.lock`, and update this guide if a different version is selected.

### R2 — Turso development checkout: forward context only

- Local path on the planning machine: `/Users/roman/Desktop/work/prj.ideas/S3MUX/TOOLS_TURSO/turso`
- Revision inspected: `2bdeb831796f62b4ff2f8393f93ddc1a17ebba50`
- Workspace version there: `0.8.0-pre.2`
- Canonical repository: <https://github.com/tursodatabase/turso.git>

Equivalent checkout if the local path is unavailable:

```sh
git clone https://github.com/tursodatabase/turso.git /tmp/turso-reference
git -C /tmp/turso-reference checkout 2bdeb831796f62b4ff2f8393f93ddc1a17ebba50
```

Read these files for ROADMAP001:

- `bindings/rust/src/lib.rs` — builder/database/statement API.
- `bindings/rust/src/connection.rs` — connection operations.
- `bindings/rust/src/transaction.rs` — current `Concurrent` transaction variant and `BEGIN CONCURRENT` mapping.
- `bindings/rust/src/rows.rs`, `params.rs`, `value.rs` — rows and values.
- `bindings/rust/Cargo.toml` — current features.
- `COMPAT.md` — current SQLite compatibility and Turso PRAGMAs.
- `docs/manual.md` — transaction/MVCC narrative; verify against source because portions may lag implementation.
- `CHANGELOG.md` — behavior introduced after earlier releases.
- `rust-toolchain.toml` — upstream toolchain context, not automatically Tursox's toolchain.

Do not copy path dependencies from this checkout. A feature seen here but missing from R1 is deferred or implemented through public SQL only after a test proves it on R1.

Planning-time working-tree note: the R2 and R4 checkouts were clean; R3 had only an unrelated tracked `.envrc` deletion; R5 had only an untracked `AGENTS.md`. Findings came from the listed tracked files at the recorded commits. To bypass any later local edits, use `git -C <checkout> show <revision>:<path>` or make the clean equivalent checkout shown below.

### R3 — Existing `ex_turso`: code to mine selectively

- Local path: `/Users/roman/Desktop/work/prj.ideas/S3MUX/TOOLS_TURSO/concord/apps/ex_turso`
- Parent repository revision inspected: `9400a1fc49e4a06511f4fcbfb62a3d17c50f6c02`
- Canonical repository: <https://github.com/gsmlg-dev/concord.git>
- Subdirectory: `apps/ex_turso`

Equivalent checkout:

```sh
git clone https://github.com/gsmlg-dev/concord.git /tmp/concord-reference
git -C /tmp/concord-reference checkout 9400a1fc49e4a06511f4fcbfb62a3d17c50f6c02
```

Read:

- `mix.exs` — dependencies/package layout.
- `lib/turso/native.ex` — RustlerPrecompiled declarations.
- `lib/turso/connection.ex` — DBConnection callbacks and current ownership flaw.
- `lib/turso/query.ex`, `result.ex`, `error.ex` — protocol/result/error shapes.
- `native/ex_turso/Cargo.toml` — native dependency choices.
- `native/ex_turso/src/lib.rs` — resources, Tokio runtime, parameter conversion, and full-result materialization.
- `README.md` and tests — claimed behavior and usage.

Use only the patterns explicitly approved in ROADMAP001 section 3. In particular, do not copy its per-pool-worker database open or full-result collection.

### R4 — Exqlite: SQLite-shaped Elixir API reference

- Local path: `/Users/roman/Desktop/work/prj.ideas/S3MUX/TOOLS_TURSO/exqlite`
- Revision inspected: `f92573ba188a4794ddc70e9a76c7e375d579f6a9`
- Canonical repository: <https://github.com/elixir-sqlite/exqlite.git>
- Public docs: <https://hexdocs.pm/exqlite/>

Equivalent checkout:

```sh
git clone https://github.com/elixir-sqlite/exqlite.git /tmp/exqlite-reference
git -C /tmp/exqlite-reference checkout f92573ba188a4794ddc70e9a76c7e375d579f6a9
```

Read:

- `lib/exqlite/sqlite3.ex` — low-level open/prepare/bind/step/reset/release API and blob tagging.
- `lib/exqlite/connection.ex` — DBConnection, transaction, pragma, cursor, and connection options.
- `lib/exqlite/stream.ex`, `query.ex`, `result.ex`, `error.ex` — streaming and result conventions.
- `README.md` — caveats and examples.
- `test/exqlite/sqlite3_test.exs`, `connection_test.exs`, `cancellation_test.exs` — contract examples.

Tursox borrows familiarity, not module names or drop-in compatibility. Turso's separate `Database` and `Connection` resources remain visible.

### R5 — Parquex: project/release structure reference

- Local path: `/Users/roman/Desktop/work/prj.ideas/S3MUX/parquex`
- Revision inspected: `1b89b6d5ecf6ac23ac2c0a3ca53fee40a6c4c433`
- Canonical repository: <https://github.com/mindreframer/parquex.git>

Equivalent checkout:

```sh
git clone https://github.com/mindreframer/parquex.git /tmp/parquex-reference
git -C /tmp/parquex-reference checkout 1b89b6d5ecf6ac23ac2c0a3ca53fee40a6c4c433
```

Read:

- `mix.exs` — package/docs/dependency organization.
- `lib/parquex/native.ex` — source-build versus precompiled NIF selection.
- `native/parquex_nif/Cargo.toml` and `Cargo.lock` — exact native pins.
- `rust-toolchain.toml` and `.cargo/config.toml` — toolchain/build setup.
- `bin/qa_check.sh` — authoritative gate structure.
- `bin/package_precompiled_nif.sh`, `bin/smoke_precompiled_nif.exs`, and `bin/smoke_precompiled_consumer.exs` — artifact verification.
- `.github/workflows/ci.yml` and `.github/workflows/precompiled-release.yml` — pinned CI and target matrix.
- `@meta/@pm/ROADMAP001.md` and child epic files — roadmap format only.

Copy no domain code and no published checksum. Adapt names, native dependencies, targets, licenses, and smoke behavior to Tursox.

### R6 — Rustler and RustlerPrecompiled

- Rustler source/docs: <https://github.com/rusterlium/rustler> and <https://hexdocs.pm/rustler/>
- RustlerPrecompiled source/docs: <https://github.com/philss/rustler_precompiled> and <https://hexdocs.pm/rustler_precompiled/>

The exact Hex versions are selected and locked in Epic 1. Consult version-matched docs after selection, especially resource destructors, dirty schedulers, panic behavior, NIF version targeting, checksums, and force-build options.

### R7 — DBConnection

- Hex docs: <https://hexdocs.pm/db_connection/DBConnection.html>
- Source: <https://github.com/elixir-ecto/db_connection>

The exact Hex version is selected and locked before Epic 5. Required callbacks are `connect`, `disconnect`, `checkout`, `ping`, status, prepare/execute/close, declare/fetch/deallocate, and begin/commit/rollback. Version-matched behavior and callback return tuples must be verified rather than inferred from `ex_turso` or Exqlite.

### R8 — SQLite semantic vocabulary

These links define the familiar SQLite concepts Turso aims to emulate; Turso's exact-version behavior still wins when it differs:

- transactions: <https://www.sqlite.org/lang_transaction.html>
- bound parameters: <https://www.sqlite.org/lang_expr.html#parameters>
- result/error codes: <https://www.sqlite.org/rescode.html>
- journal mode: <https://www.sqlite.org/pragma.html#pragma_journal_mode>
- WAL checkpoint: <https://www.sqlite.org/pragma.html#pragma_wal_checkpoint>
- C API lifecycle overview: <https://www.sqlite.org/cintro.html>

Use R8 for naming and expected SQLite shape, not as proof that Turso `0.7.2` implements a feature. R1 runtime tests and Turso's versioned compatibility information are required.

### R9 — Elixir release and observability references

- Telemetry: <https://hexdocs.pm/telemetry/>
- ExDoc: <https://hexdocs.pm/ex_doc/>
- Hex package creation: <https://hex.pm/docs/publish>
- Mix project reference: <https://hexdocs.pm/mix/Mix.Project.html>

Select and lock exact package versions in the epic that introduces them. Version-matched package behavior overrides examples in R5.

## 4. Encoded Technical Findings

These findings explain the roadmap decisions and let an agent proceed even when sibling checkouts are absent.

### F1 — Stable Turso resource hierarchy

In `turso 0.7.2`, `Builder::new_local(path).build().await` returns a cloneable `Database`. `Database::connect(&self)` returns a `Connection`. A single database can therefore derive multiple connections. Tursox must retain this hierarchy instead of rebuilding a database for each pool worker.

### F2 — Stable query and cursor surface

`Connection` exposes async `query`, `execute`, `execute_batch`, `prepare`, `prepare_cached`, `pragma_query`, and `pragma_update`; synchronous `last_insert_rowid`, `cacheflush`, `is_autocommit`, and `busy_timeout` are also public. `Statement::query` returns `Rows`, and `Rows::next().await` yields one row at a time. This supports a bounded native cursor resource.

`Rows` owns a cloned `Statement`, while cloned statements share internal state. Tursox must prevent reset/re-execution while a cursor is active rather than allowing one clone to reset another active scan.

### F3 — Values and parameters

The stable value variants are `Null`, `Integer(i64)`, `Real(f64)`, `Text(String)`, and `Blob(Vec<u8>)`. `IntoParams` supports none, positional values, and named values. Named keys include their SQLite prefix (`:name`, `@name`, `$name`, or numbered forms). Tursox uses ordered lists and explicit `{:blob, binary}` tagging so Elixir UTF-8 text and arbitrary bytes are not conflated.

### F4 — Stable errors

`turso 0.7.2` publicly distinguishes `Busy`, `BusySnapshot`, `Interrupt`, `Constraint`, `Readonly`, `DatabaseFull`, `Misuse`, `NotAdb`, `Corrupt`, `IoError`, and conversion/general errors. Preserve these distinctions in `Tursox.Error`; do not copy `ex_turso`'s collapse of `BusySnapshot` into `:busy`.

### F5 — Concurrent transaction version gap

`turso 0.7.2`'s public `TransactionBehavior` enum contains `Deferred`, `Immediate`, and `Exclusive`; it does **not** contain `Concurrent`. The inspected `0.8.0-pre.2` source adds `Concurrent` and maps it to `BEGIN CONCURRENT`.

Therefore Epic 4 must not reference a nonexistent `0.7.2` enum variant. Implement Tursox `mode: :concurrent` through the public SQL execution path (`BEGIN CONCURRENT`) and explicit commit/rollback state, or change the pinned crate only after documenting and testing that decision. `PRAGMA journal_mode = mvcc` must be set and verified first.

### F6 — MVCC configuration and checkpointing

For the inspected engine, MVCC is selected with `PRAGMA journal_mode = mvcc`; concurrent transactions provide snapshot isolation and commit-time conflict detection. `PRAGMA mvcc_checkpoint_threshold` and `PRAGMA wal_checkpoint(...)` exist in the engine compatibility material. `Builder::experimental_mvcc_passive_checkpoint` exists in stable `0.7.2`.

Presence in engine SQL does not guarantee every mode/result shape works through the stable Rust binding. Epic 4 must run executable probes and encode exact accepted inputs/results before exposing helpers.

### F7 — Runtime and cancellation limitation

The stable Rust `Connection` surface inspected for ROADMAP001 has no public high-level `interrupt` or query-timeout method, although lower-level/current language bindings may have such behavior. Do not reach into `turso::core` merely to claim a stable cancellation API. Use bounded cursor fetches and busy timeout, document the limitation, and only expose interruption if the exact pinned public API supports it.

### F8 — Crate features and allocator

`turso 0.7.2` defaults to `mimalloc` and `fts`. Its `mimalloc` feature declares a global allocator in the Rust binding crate. Epic 1 must deliberately decide whether the NIF uses `default-features = false` and selectively enables `fts`; it must not inherit a process-wide allocator accidentally. Cloud `sync` is optional and deferred by ROADMAP001.

### F9 — Why `ex_turso` is insufficient

The inspected wrapper opens a new `Database` inside each `DBConnection.connect/1`, drives all async work through one global Tokio runtime with `block_on`, returns all query rows in one NIF call, creates row maps by default, treats prepare/close as no-ops in DBConnection, forces source builds, enables index methods unconditionally, and collapses busy snapshot classification. Its resource/error scaffolding is useful, but those behaviors conflict with ROADMAP001 invariants.

### F10 — Packaging is independent of sibling repositories

Parquex demonstrates the desired structure, but Tursox must own all copied/adapted scripts and workflows. Clean CI, package builds, source builds, and no-Rust consumers must work after deleting every R2–R5 checkout.

## 5. Required Epic 1 Capability Record

Before Phase 1.2 is checked, add a repository-owned versioned document (suggested path `docs/compatibility/turso-0.7.2.md`) containing:

- exact `turso`, `turso_core`, `turso_sdk_kit`, Tokio, Rustler, and Rust toolchain resolutions;
- selected Cargo features and why;
- compiler-supported targets;
- every public Builder method Tursox exposes;
- connection, statement, rows, params, value, and error APIs actually used;
- transaction modes and the special SQL implementation for `:concurrent` if still required;
- runtime-probed MVCC PRAGMA inputs/result shapes;
- APIs intentionally absent, especially interrupt/query timeout, changes/total_changes if unavailable, and sync;
- links to exact docs/source and the date verified; and
- minimal compile/runtime tests that prove each claim.

If the selected engine version changes, update ROADMAP001, this guide, the capability record, Cargo files, tests, and compatibility documentation in the same epic. Never silently implement against `main` while claiming a stable crates.io baseline.
