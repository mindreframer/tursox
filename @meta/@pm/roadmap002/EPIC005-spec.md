# EPIC005 Spec: Views and Advanced Schema Features

## Purpose

Verify Turso's advanced schema capabilities and their behavior across transactions, connections, and database reopen.

## Reference

<https://docs.turso.tech/sql-reference/statements/create-materialized-view>

## Scope

In scope:

- ordinary views and create/drop behavior
- materialized views, supported query shapes, and automatic incremental maintenance
- commit/rollback consistency between base tables and materialized results
- generated columns and indexes over generated results where supported
- trigger create/drop and transactional effects
- `WITHOUT ROWID` tables
- attach/detach and schema isolation
- vacuum/autovacuum availability and file/integrity behavior
- introspection of every supported schema object

Out of scope:

- migration orchestration
- unsupported materialized-view refresh emulation
- performance guarantees beyond bounded sanity checks

## Schema Contract

Experimental options are explicit at database open. Schema features must behave consistently across multiple connections and reopen. Materialized data must never expose updates that were rolled back. Attached databases must not violate Tursox resource ownership or leak files.

## Acceptance Criteria

- Supported view forms create, query, introspect, and drop correctly.
- Materialized views track supported inserts, updates, and deletes without manual refresh.
- Materialized-view changes commit and roll back atomically with base changes.
- Unsupported definitions fail with stable errors and no corrupted schema.
- Generated columns, triggers, and `WITHOUT ROWID` pass representative lifecycle tests.
- Attach/detach and vacuum behavior are classified and tested where available.
- Reopen and integrity checks pass after schema workloads.

## Test Strategy

Use feature-on/off fixtures, multiple connections, aggregate and filtered views, explicit transaction rollback, malformed definitions, dependency/drop ordering, attached temporary files, size/integrity checks, and reopen verification.
