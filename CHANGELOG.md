# Changelog

## 0.1.0 - Unreleased

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
