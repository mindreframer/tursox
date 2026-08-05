# EPIC007 Spec: Multiprocess Access and Compatibility Release

## Purpose

Verify experimental multiprocess WAL with real OS processes, consolidate the capability baseline, and release Tursox `0.2.0` without changing the Turso engine version.

## Reference

<https://docs.turso.tech/sql-reference/multiprocess-access>

## Scope

In scope:

- supported-platform and filesystem preflight behavior
- independent BEAM/OS-process readers and writers sharing one file
- writer serialization, reader snapshots, checkpoints, schema changes, and prepared-statement invalidation
- process termination, reopen, stale sidecar handling, and integrity
- single-process/multiprocess mode mixing failures
- rejection of memory databases and MVCC combinations
- `.db-wal` and `.db-tshm` lifecycle observations
- final generated capability matrix, documentation, changelog, version synchronization, QA, and release artifacts

Out of scope:

- promising multiprocess behavior on unsupported targets or network filesystems
- stabilizing Turso's experimental on-disk coordination format
- distributed databases or a server protocol
- a Turso engine upgrade

## Multiprocess Contract

Multiprocess claims require separate OS processes; multiple connections in one BEAM are insufficient. Platform-limited tests must skip with an explicit reason, not report success. Child processes must have time bounds and deterministic synchronization, and doomed children must be terminated and reaped.

## Acceptance Criteria

- Two supported OS processes can read and write one database with expected WAL visibility.
- Writers serialize and readers retain stable snapshots.
- Crashed/terminated participants do not leave the database corrupt.
- Mode mixing, memory use, MVCC combinations, and unsupported environments are rejected or classified exactly.
- Sidecar behavior and cleanup are documented.
- The final capability report is generated from or checked against executable test data.
- Mix/Cargo versions and docs agree on `0.2.0` while Turso remains `0.7.2`.
- Full QA and every advertised precompiled target smoke test pass.

## Test Strategy

Use repository-owned child-process scripts, barriers/files or ports rather than sleeps, strict timeouts, kill/recovery cases, integrity checks, platform tags, clean temporary directories, and source/precompiled consumer tests.
