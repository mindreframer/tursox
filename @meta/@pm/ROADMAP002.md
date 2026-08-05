# ROADMAP002 — Turso Capability Coverage and Regression Confidence

- **Status:** Planned
- **Target:** `0.2.0`
- **Engine baseline:** keep the currently pinned `turso = 0.7.2`
- **Primary outcome:** expose and verify more Turso SQL capabilities through Tursox

## 1. Goal

Make Tursox a conservative, executable compatibility layer for the Turso features applications can use today. This roadmap expands feature access where the pinned Rust API permits it, tests documented SQL behavior through the Elixir bindings, records unsupported or unsafe behavior honestly, and creates a regression baseline for future Turso upgrades.

This is a quality-of-life and capability roadmap. It does not upgrade Turso.

## 2. Documentation Baseline

Use these Turso references as the feature checklist:

- Data types and custom types: <https://docs.turso.tech/sql-reference/data-types>
- Materialized views: <https://docs.turso.tech/sql-reference/statements/create-materialized-view>
- Domains: <https://docs.turso.tech/sql-reference/statements/create-domain>
- Full-text search: <https://docs.turso.tech/sql-reference/functions/fts>
- Multiprocess access: <https://docs.turso.tech/sql-reference/multiprocess-access>
- Extensions: <https://docs.turso.tech/sql-reference/extensions>
- PRAGMAs: <https://docs.turso.tech/sql-reference/pragmas>
- Experimental features: <https://docs.turso.tech/sql-reference/experimental-features>

The web documentation may describe behavior newer than `0.7.2`. The exact locked crate source and executable Tursox tests are authoritative. Every checked feature must be classified as working, partially working, unsupported by the pin/build, platform-limited, or unsafe.

## 3. Principles

1. Do not change the Turso engine version in this roadmap.
2. Test behavior through public Tursox APIs, not only directly in Rust.
3. Keep generic SQL available; add helpers only where they improve safety or feature discovery.
4. Experimental features remain explicit opt-ins.
5. Documentation claims require executable tests on the pinned engine.
6. High-risk native probes run in disposable OS processes so an engine crash cannot take down the main ExUnit VM.
7. Preserve ordered rows, bounded cursors, stable errors, and the one-database/many-connections model from ROADMAP001.
8. Record documentation mismatches rather than hiding or working around them silently.

## 4. In Scope

- broad core SQL regression tests through direct and pooled bindings
- documented PRAGMA query/update behavior and result shapes
- safe PRAGMA forms that require table/index arguments
- an executable experimental-feature capability matrix
- STRICT tables, built-in/custom types, arrays/composite types where available, and domains
- views, materialized views, generated columns, triggers, `WITHOUT ROWID`, attach/detach, and vacuum behavior
- Turso FTS build support, indexes, matching, scoring, highlighting, and maintenance
- inventory and smoke coverage for built-in/loadable Turso extensions
- real multi-process WAL tests on supported platforms
- generated compatibility documentation suitable for comparing a future engine upgrade

## 5. Explicitly Deferred

- upgrading `turso` or adopting prerelease engine code
- Ecto adapters and migration frameworks
- Turso Cloud sync and remote databases
- custom Elixir/Rust SQL functions, collations, VFS implementations, and arbitrary native extension loading
- network services and tenant routing policy
- claiming experimental Turso features are production-stable
- emulating features absent from the pinned engine

## 6. Capability Result Contract

Each tested capability must record:

- required database feature flags and Cargo features;
- direct, pooled, file, memory, and platform applicability;
- successful SQL and observed ordered result shape;
- disabled-feature and invalid-input behavior;
- transaction, reopen, or multi-connection behavior where relevant;
- known limitations or documentation differences; and
- a stable status: `supported`, `partial`, `unsupported`, `platform_limited`, or `unsafe`.

Unsupported results are valid findings. They become failures only when an already-supported capability regresses unexpectedly.

## 7. Epics

### Epic 1 — Core SQL and Database Regression Suite

Prove ordinary database behavior through Tursox: DDL, CRUD, constraints, expressions, joins, transactions, prepared statements, persistence, concurrency, pools, and representative manager access.

### Epic 2 — PRAGMA Coverage and Introspection

Exercise documented metadata, schema, configuration, integrity, WAL/MVCC, CDC, encryption, and custom-type PRAGMAs, extending safe argument support where required.

### Epic 3 — Experimental Feature Capability Matrix

Test every documented experimental switch disabled and enabled, align available Rust builder options with `Tursox.Database`, and publish exact capability statuses.

### Epic 4 — STRICT Tables, Custom Types, and Domains

Verify STRICT behavior, built-in and user-defined types, encoding/decoding, constraints, arrays/composites where available, domains, introspection, and lifecycle restrictions.

### Epic 5 — Views and Advanced Schema Features

Verify standard/materialized views, incremental maintenance, generated columns, triggers, `WITHOUT ROWID`, attach/detach, and vacuum behavior.

### Epic 6 — Full-Text Search and Extensions

Enable the pinned build support required for Turso FTS, test its full lifecycle, and inventory/smoke-test the extensions actually available in the embedded build.

### Epic 7 — Multiprocess Access and Compatibility Release

Run real multi-process WAL scenarios, document platform and mode restrictions, consolidate the executable compatibility report, and release `0.2.0`.

## 8. Dependency Order

```text
Epic 1: core behavioral baseline
   ↓
Epic 2: PRAGMA and introspection surface
   ↓
Epic 3: experimental feature switches
   ↓
Epic 4: types and domains
   ↓
Epic 5: advanced schema behavior
   ↓
Epic 6: FTS and extensions
   ↓
Epic 7: multiprocess verification + compatibility release
```

## 9. Quality Policy

After every epic:

1. Run `bin/qa_check.sh`.
2. Run any epic-specific subprocess or platform test command.
3. Check phases only after code, tests, and acceptance criteria pass.
4. Update the capability report with observed behavior.
5. Commit as `roadmap002 - epic N - <outcome>`.

Tests must be deterministic, use unique temporary databases, avoid sleeps for concurrency ordering, and clean up database/WAL/Turso sidecar files. Features that can crash or abort the native runtime must be probed outside the main BEAM test process.

## 10. Definition of Success

Tursox `0.2.0` succeeds when users can determine, from tested documentation, which core SQL, PRAGMA, experimental, custom-type, schema, FTS, extension, and multiprocess capabilities work through the pinned bindings; use the supported capabilities with clear opt-ins; and rely on the suite to detect behavior changes during a future Turso upgrade.
