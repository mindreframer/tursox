# EPIC001 Spec: Core SQL and Database Regression Suite

## Purpose

Establish a conservative behavioral baseline for ordinary Turso database use through Tursox before testing specialized extensions.

## Scope

In scope:

- table/index DDL and schema changes
- insert, select, update, delete, upsert, returning, and batch execution where supported
- nulls, all five storage classes, affinity, defaults, expressions, ordering, grouping, joins, subqueries, and compound queries
- primary key, unique, check, not-null, and foreign-key behavior
- prepared statements, positional/named binding, cursor chunking, and reset/reuse
- transaction commit/rollback and visibility across derived connections
- file persistence/reopen, in-memory sharing, pools, and representative manager access
- stable error classification and cleanup after failures

Out of scope:

- exhaustive SQLite conformance
- Ecto, migrations, custom codecs, and performance claims
- specialized features assigned to later epics

## Regression Contract

Tests must exercise public Tursox APIs. Representative cases run through direct connections and `Tursox.Pool`; manager tests prove routing to the same tested database behavior without duplicating the complete suite. Assertions cover ordered values, result metadata, transaction visibility, and stable error codes rather than fragile engine prose.

## Acceptance Criteria

- Core DDL and CRUD scenarios pass for file and memory databases.
- Constraints and rollback leave no partial writes.
- Prepared/bound queries preserve values and ordered rows.
- Multiple connections observe commit boundaries correctly.
- Reopen tests prove durable committed data and absent rolled-back data.
- Pool and manager smoke scenarios agree with direct behavior.
- Failures leak no logical native resources.

## Test Strategy

Use table-driven ExUnit cases, boundary values, Unicode/blob data, deterministic connection barriers, unique temporary directories, and resource snapshots. Document unsupported SQL rather than weakening assertions silently.
