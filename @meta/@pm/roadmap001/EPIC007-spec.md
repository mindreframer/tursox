# EPIC007 Spec: Hardening, Documentation, and Initial Release

## Purpose

Stabilize the direct, pooled, MVCC, and multi-database APIs and release `0.1.0` with verified precompiled native artifacts.

## Required References

Read `@meta/@pm/roadmap001/REFERENCES.md`, especially R5's exact scripts/workflows and finding F10, plus R6's version-matched RustlerPrecompiled artifact/checksum rules. R5 supplies structure only; Tursox target support must be independently built and smoked.

## Scope

In scope:

- public API review and compatibility table
- telemetry for database/connection/query/transaction/cursor/manager lifecycle
- scheduler responsiveness, bounded-memory, contention, lifecycle, and fault tests
- safe logs/errors/inspection audits
- README, guides, architecture docs, changelog, license/notices, and security policy
- package metadata
- CI matrix and precompiled NIF pipeline structurally informed by the exact R5 files cataloged in `REFERENCES.md`
- source-build and no-Rust precompiled consumer smoke tests
- synchronized `0.1.0` versioning and release artifacts

Out of scope:

- adding deferred features to make the release appear broader
- claiming upstream MVCC stability beyond Turso's statement
- publishing without every target and consumer smoke test green

## Observability Contract

Telemetry contains operation names, durations, counts, safe database/tenant identifiers as configured by the caller, result/error classes, fetch row counts, retry attempts, and resource gauges. It contains no SQL by default and never contains bound params, rows, keys, tokens, or raw database contents.

## Release Contract

Supported targets are selected based on reproducible successful builds, expected initially:

- macOS aarch64 and x86_64
- Linux aarch64/x86_64 GNU and musl
- Windows x86_64 MSVC

Each artifact is built from the release commit, packaged under the exact RustlerPrecompiled name, raw-smoke tested, then consumed from an unpacked Hex package with Rust unavailable. Checksums are generated from published artifacts only. Source builds remain supported via an explicit environment variable.

## Acceptance Criteria

- All public examples execute in tests.
- Large-result memory remains within the documented fetch envelope.
- Many-database and MVCC contention tests leave no resources or sidecar files unexpectedly open.
- Telemetry/errors/logs contain no sensitive values.
- Docs state direct versus pooled versus managed tradeoffs and the exact compatibility/experimental limits.
- Every advertised precompiled target passes raw and package-consumer smoke tests.
- Version, Cargo/Mix metadata, lockfiles, README, and changelog agree on `0.1.0`.
- Final QA passes from a clean checkout.

## Test Strategy

Add oversize result sets, large blobs, high tenant counts, rapid churn, MVCC conflicts, pool shutdown under load, malformed/corrupt database behavior, unsupported option fuzzing, telemetry capture/redaction, docs tests, and precompiled no-Rust consumers.
