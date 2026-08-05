# Changelog

## 0.2.1 - 2026-08-05

### Added

- Runtime opt-ins for all eleven documented Turso experimental flags, including
  encryption, autovacuum, and unsafe MVCC passive checkpointing.
- Secret-redacted local encryption with all eight pinned cipher modes and
  portable crypto in every source/precompiled build.
- Explicit `unsafe_features` for process-killing schema/checkpoint paths while
  preserving the 0.2.x `features` aliases.
- Explicit native runtime extension loading through Turso's extension ABI.
- Phase-marked subprocess evidence that distinguishes successful execution,
  setup errors, timeouts, SIGBUS, and SIGSEGV.

### Fixed

- Replaced permissive tests that treated any nonzero child exit as proof of an
  engine crash; probes now assert the exact last phase and exit class.
- Exposed the pinned SDK's autovacuum gate through a minimal exact-0.7.2 wrapper
  patch and documented its still-broken fresh-file persistence behavior.
- Corrected the encryption and MVCC capability claims from “not exposed” to
  tested runtime options.
- Verified that SQLean 0.28.3 exports SQLite entry points and is rejected by
  Turso's loader because it does not export Turso's `register_extension` ABI.

## 0.2.0 - 2026-08-05

### Added

- Executable core SQL regression baseline across direct, pooled, managed, file,
  memory, transaction, persistence, and resource-lifecycle paths.
- Injection-safe argument-bearing PRAGMA API and documented metadata,
  configuration, integrity, WAL/MVCC, gated, and unsupported result shapes.
- Machine-readable experimental capability metadata and generated pinned-engine
  report with subprocess containment for crash-prone probes.
- STRICT base-type, ordinary view, generated-column safety, trigger,
  `WITHOUT ROWID`, attach/detach, vacuum, and reopen/integrity coverage.
- Deliberate Tantivy-backed FTS build support with matching, scoring,
  highlighting, tokenizers, weights, DML, transaction, optimize, and reopen tests.
- Runtime-derived UUID, regexp, vector, time, percentile, series, unavailable
  extension, and disabled runtime-loading inventory.
- Real 64-bit Unix multiprocess WAL child-process tests for snapshots, writer
  serialization, checkpoint/schema refresh, crash recovery, sidecars, and exact
  0.7.2 documentation differences.

### Changed

- Split the native NIF implementation into cohesive builder, database, query,
  resource, value, error, runtime, smoke, and atom modules.
- Precompiled consumer smoke now verifies FTS and representative built-ins.

## 0.1.0 - 2026-08-05

### Added

- Reproducible Rustler/Turso native foundation.
- Direct, pooled, and managed public architecture contracts.
- Opaque local/in-memory database and derived connection resources with
  validated builder options, safe pragmas, logical close, and resource gauges.
- Strict SQLite values and parameters, native prepared statements, ordered
  metadata, bounded incremental cursors, lazy streams, and explicit map conversion.
- Rollback-safe transaction callbacks, four transaction modes, experimental MVCC
  conflict classification and whole-callback retry, checkpoint threshold, and WAL checkpoints.
- Optional shared-handle DBConnection pools with real per-worker preparation,
  bounded streams, transaction modes, worker replacement, and deterministic ownership cleanup.
- Caller-supervised multi-database managers with atomic admission, canonical-path
  protection, capacity limits, bounded close, persistent restart, safe listing, and no dynamic atoms.
- Redacted duration/result telemetry and deterministic native resource gauges.
- Seven-target NIF 2.16 build/smoke workflow, no-Rust consumer gate, release integrity
  documentation, and third-party notices.
