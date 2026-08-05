# EPIC002 Spec: PRAGMA Coverage and Introspection

## Purpose

Turn Turso's documented PRAGMA surface into executable compatibility tests and safe Tursox access patterns.

## Reference

<https://docs.turso.tech/sql-reference/pragmas>

## Scope

In scope:

- database metadata: database/page/freelist counts, page size, encoding, schema/application/user versions
- schema introspection: table/index information and lists, function and PRAGMA inventories
- configuration: journal, cache, synchronous, temp, busy, query-only, foreign keys, check constraints, sync retry, and require-where behavior
- integrity and quick checks
- WAL/MVCC checkpoint and tuning PRAGMAs
- CDC, encryption, and custom-type PRAGMA availability
- safe support for PRAGMAs that take table/index names or structured arguments
- result-shape, scope, persistence, invalid-value, and unsupported-status documentation

Out of scope:

- promising every SQLite PRAGMA
- unsafe raw string interpolation for identifiers or arguments
- treating documentation presence as proof of pinned-engine support

## PRAGMA Contract

Tursox must distinguish query, update, and argument-bearing PRAGMAs safely. Each tested PRAGMA records whether it is connection-local, database-persistent, feature-gated, journal-specific, or unsupported. Secret encryption keys must never appear in errors, telemetry, or inspection output.

## Acceptance Criteria

- Every PRAGMA listed in the roadmap checklist has an executable status.
- Supported PRAGMAs have exact ordered result-shape assertions.
- Table/index introspection works without accepting injectable identifiers.
- Scope and reopen behavior are tested where applicable.
- Invalid and read-only operations return stable errors.
- Integrity checks pass after representative database workloads.
- Unsafe or crashing operations are isolated in subprocess probes and classified.

## Test Strategy

Use fresh file and memory databases, multiple connections, reopen checks, feature-gated fixtures, quoted identifiers, invalid values, and disposable subprocesses for hazardous native paths.
