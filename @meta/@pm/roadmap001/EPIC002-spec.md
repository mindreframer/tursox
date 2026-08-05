# EPIC002 Spec: Database and Connection Resources

## Purpose

Expose Turso's database/connection split faithfully so one open database can safely create many independently configured connections.

## Required References

Read `@meta/@pm/roadmap001/REFERENCES.md`, especially R1 files `src/lib.rs` and `src/connection.rs`, plus findings F1, F2, F6, F7, and F8. R2 is forward context only.

## Scope

In scope:

- local file and isolated in-memory database resources
- path normalization, parent-directory creation policy, and read/write/create validation supported by Turso
- validated builder feature options available in the pinned stable Rust API
- explicit `Database.connect/2`, database metadata, connection settings, and idempotent close
- busy timeout, autocommit/status, cache flush, and safe pragma query/update primitives where supported
- resource ancestry and counters

Out of scope:

- SQL result APIs beyond minimal connection verification
- prepared statements and row cursors
- transaction helpers and MVCC correctness (except option validation plumbing)
- DBConnection and manager processes
- cloud sync, serverless, custom IO/VFS, and production multiprocess support

## Resource Contract

A `Tursox.Database` struct is an opaque Elixir wrapper over one native database resource. `Database.connect/2` derives native connections from that same resource. Opening `:memory` creates one database whose derived connections share that in-memory state; separate opens remain isolated.

Logical close is explicit and idempotent. Once a database closes it rejects new connections. Existing descendants never crash or access freed memory; their documented behavior is either safe invalidation or continued lifetime until explicitly closed, selected and tested in this epic. Connection operations serialize mutable state without a global database lock.

## Builder Options

Expose only options confirmed on the exact crate, with stable Elixir names and strict type validation. Candidate features include attach, custom types, generated columns, index methods, materialized views, vacuum, multiprocess WAL, `WITHOUT ROWID`, encryption, and MVCC passive checkpointing. Unsupported or incompatible combinations return `:unsupported`/`:invalid_argument`; they are never silently ignored.

## Acceptance Criteria

- One file database produces multiple working connections from one database resource.
- Connections from one in-memory database see the same data; separately opened memory databases do not.
- Many database resources remain isolated when open concurrently.
- Invalid paths/options fail without leaks or partial hidden resources.
- Closing every resource is idempotent and resource counters return to baseline.
- Per-connection busy timeout and supported status/flush/pragma primitives work.
- Builder options are versioned and documented, including experimental warnings.

## Test Strategy

Use unique temporary directories for persistence, Unicode paths, missing parents, read-only cases if supported, repeated open/close, parent-before-child close, 100+ simultaneous memory databases, and concurrent connection creation from one database.
