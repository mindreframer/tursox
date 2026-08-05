# EPIC003 Spec: Experimental Feature Capability Matrix

## Purpose

Provide an executable answer for which documented Turso experimental features are accessible through the pinned Rust crate and Tursox build.

## Reference

<https://docs.turso.tech/sql-reference/experimental-features>

## Scope

Evaluate:

- views/materialized views
- custom types and domains
- encryption
- index methods
- autovacuum and vacuum
- attach/detach
- generated columns
- `WITHOUT ROWID`
- multiprocess WAL
- MVCC passive checkpointing
- features documented as no longer experimental, including triggers

For each feature, inspect the exact `0.7.2` Builder/Cargo surface, align `Database.builder_features/0`, validate options, and run a minimal disabled/enabled behavior probe.

Out of scope:

- enabling unavailable features through internal `turso_core` APIs
- changing the Turso version
- claiming experimental features are production-safe

## Capability Contract

Each feature receives one stable status: `supported`, `partial`, `unsupported`, `platform_limited`, or `unsafe`. The record includes the public Rust switch, Tursox option, required Cargo feature, probe SQL, observed result, and limitation. A documented feature absent from `0.7.2` remains unsupported rather than emulated.

## Acceptance Criteria

- Every documented feature has a status and executable probe.
- Supported builder switches are exposed and validated consistently.
- Disabled-feature behavior is tested where the engine enforces a gate.
- Unknown and incompatible combinations fail before hidden allocation where practical.
- Existing supported feature names do not regress.
- Hazardous probes cannot crash the main test VM.
- The public capability document matches the tests.

## Test Strategy

Use data-driven feature cases, exact crate-source inspection, temporary databases, subprocess probes, and platform tags. Later epics deepen behavior for types, views, FTS, and multiprocess access.
