# EPIC005 Spec: Shared-Handle DBConnection Pool

## Purpose

Provide an idiomatic pooled API without repeating `ex_turso`'s one-database-open-per-worker design.

## Scope

In scope:

- `DBConnection` query/result protocol structs
- a pool start path that opens or receives one database resource, then derives all worker connections from it
- execute, prepare, close, declare/fetch/deallocate, ping, status, and transaction callbacks
- bounded DBConnection streams backed by native cursors
- deferred/immediate/exclusive/concurrent transaction options
- checkout isolation and connection replacement after fatal native errors
- direct access to the underlying pool as an optional layer

Out of scope:

- Ecto adapter callbacks and migration locking
- a global/default repository
- reopening the database path in each worker
- cloud sync

## Pool Contract

Starting a Tursox pool creates exactly one logical database resource. `pool_size` controls derived connections, not database opens. The owner resource outlives workers and is released after the pool drains. A supplied database resource remains caller-owned unless an explicit ownership option says otherwise.

DBConnection checkout gives exclusive use of one connection, which prevents transaction interleaving. Cursor streaming fetches bounded chunks and deallocates on halt. Fatal `:io`, `:corrupt`, or closed-resource failures disconnect a worker; retryable busy/constraint errors do not.

In-memory pools share one in-memory database across all workers.

## Acceptance Criteria

- Resource counters show one database and `pool_size` connections.
- A pool_size greater than one shares file and in-memory state.
- DBConnection execute/query/prepare/stream contracts work with ordered rows.
- Stream early halt releases the native cursor.
- Every transaction mode is forwarded, including concurrent MVCC.
- Checkout contention does not interleave operations on one connection.
- Fatal errors replace only the affected worker; pool shutdown releases owned resources.
- Direct APIs remain usable without starting DBConnection.

## Test Strategy

Cover pool sizes 1 and many, in-memory sharing, prepared query reuse, stream chunks, early halt, transaction rollback, MVCC concurrent transactions, worker crash/restart, pool owner crash, caller-owned database, shutdown under load, and resource counts.
