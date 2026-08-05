# EPIC004 Spec: Transactions and MVCC

## Purpose

Make transaction safety and Turso MVCC explicit, testable, and useful for concurrent embedded workloads.

## Required References

Read `@meta/@pm/roadmap001/REFERENCES.md`, especially R1 `src/transaction.rs`, R2 transaction/compatibility files, and findings F4–F7. Finding F5 is binding: stable `0.7.2` has no Rust `Concurrent` enum variant, so use tested public SQL or revise the pin explicitly.

## Scope

In scope:

- begin, commit, rollback, autocommit status, and transaction callbacks
- deferred, immediate, exclusive, and concurrent modes
- rollback on callback error, raise, throw, and managed owner failure where applicable
- journal mode selection/query with first-class `:wal` and `:mvcc`
- distinct `:busy` and `:busy_snapshot` errors
- bounded whole-transaction retry helper with configurable attempts/backoff/jitter function
- supported MVCC checkpoint threshold, passive checkpoint builder option, and checkpoint calls
- snapshot-isolation, conflict, durability/reopen, and integrity tests

Out of scope:

- distributed transactions
- retrying arbitrary individual SQL statements
- claiming serializable isolation
- hiding engine experimental status
- automatic conflict policy in the direct API

## Transaction Contract

A transaction callback owns one connection for its duration. Nested behavior is explicit: use supported savepoints if the pinned engine and adapter contract prove them; otherwise reject nesting. Callback success commits. Returned `{:error, reason}`, raised exceptions, throws, exits, and commit conflicts roll back before control returns whenever execution remains possible.

A retry reruns the complete callback on a fresh transaction and only for classified retryable errors. The helper has a finite default and never retries user exceptions, constraints, corruption, or I/O errors.

## MVCC Contract

Opening with `journal_mode: :mvcc` verifies the effective mode. Concurrent mode is valid only with MVCC. Tests use distinct connections from one database. Same-row conflicts must preserve one winner, classify the loser, and leave the losing transaction rolled back. Disjoint writes must be able to commit concurrently. A reader must observe a stable snapshot according to Turso's documented snapshot isolation.

Checkpoint APIs are exposed only if confirmed on `0.7.2`. Every experimental option and upstream limitation is documented. MVCC and multiprocess WAL are rejected together if upstream does not support the combination.

## Acceptance Criteria

- Every transaction mode emits the intended SQL and status transitions are correct.
- Callback failures never commit.
- Two concurrent MVCC writers can commit disjoint changes.
- A deterministic same-row conflict is returned as `:busy_snapshot` or a precisely documented retryable class.
- Whole-transaction retry succeeds and obeys its bound.
- Snapshot and reopen/durability tests pass, including checkpoint behavior.
- WAL behavior remains available and isolated from MVCC configuration.
- Documentation labels MVCC experimental and states snapshot isolation, not serializability.

## Test Strategy

Use barriers rather than sleeps for concurrent transaction ordering. Cover disjoint writes, same-row updates/deletes, stale snapshots, DDL restrictions, rollback paths, retry exhaustion, checkpoint threshold, reopen, `integrity_check`, and many databases mixing WAL/MVCC.
