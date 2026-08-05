# ADR 001: Native runtime and resource ownership

- Status: accepted
- Baseline: Turso 0.7.2, Rustler 0.38.0, Tokio 1.47.1, Rust 1.91.0

## Decision

Use one lazily initialized multi-thread Tokio runtime. Drive Turso futures only
from dirty-I/O NIF calls. Catch panics at NIF boundaries and translate expected
failures into maps containing `code`, `message`, and `operation`.

Represent database, connection, statement, and cursor handles as Rustler
`ResourceArc`s. A child retains its parent. Each mutable resource has its own
mutex and atomic logical-close state; there is no global operation mutex.
Closing a parent invalidates descendant operations. Close is idempotent.
Test-visible atomic counters count logically open resources.

Disable Turso default features so its optional global allocator and FTS feature
are not silently installed. Add capabilities only through deliberate exact pins.

## Consequences

A single connection is sequential, while independent connections can progress
concurrently. Dirty scheduler calls may block while awaiting the dedicated
runtime without blocking normal BEAM schedulers. Turso 0.7.2 exposes no stable
interrupt handle, so timeout cannot promise interruption of an already-running
engine future.
