# EPIC007 Plan: Hardening, Documentation, and Initial Release

## Required Reading

Read `@meta/@pm/ROADMAP001.md`, `REFERENCES.md`, and `EPIC007-spec.md` completely before Phase 7.1; R5 is structural guidance only.

## Progress

- [x] Phase 7.1: Stabilize names, options, defaults, errors, result shapes, and compatibility guarantees.
- [x] Phase 7.2: Add safe telemetry and resource/scheduler observability.
- [x] Phase 7.3: Harden fault, contention, large-result, churn, and shutdown paths.
- [x] Phase 7.4: Complete README, API guides, architecture, compatibility, security, and changelog docs.
- [x] Phase 7.5: Add the CI matrix, precompiled build, raw smoke, and no-Rust consumers.
- [x] Phase 7.6: Synchronize `0.1.0`, validate exact artifacts/checksums, and verify clean installs.
- [x] Phase 7.7: Pass final QA, publish/verify when authorized, and create the focused Epic 7 commit.

## Implementation Steps

1. Freeze the initial API after a direct/pool/manager consistency review and mark experimental surfaces.
2. Emit redacted telemetry and expose deterministic resource gauges for operations and tests.
3. Run bounded-memory, scheduler responsiveness, high-cardinality, failure, and lifecycle suites.
4. Test every documented example and publish an exact Turso/SQLite capability matrix.
5. Use only the exact R5 files cataloged in `REFERENCES.md` as CI/release structure examples; independently adapt and verify Tursox artifact names, dependencies, targets, licenses, and smoke behavior.
6. Verify every precompiled consumer with Rust hidden; synchronize release metadata.
7. Run full QA and release verification, then commit only when all advertised artifacts are proven.

## Quality Gate

- [x] API/docs/compatibility review is complete.
- [x] Telemetry and error redaction tests pass.
- [x] Memory, scheduler, churn, and fault suites pass.
- [x] Docs build cleanly.
- [x] Exact binary set passes raw and no-Rust consumer smoke tests.
- [x] Version and changelog are synchronized.
- [x] Final `bin/qa_check.sh` passes from a clean checkout.

## Commit Rule

Commit as `roadmap001 - epic 7 - release Tursox 0.1.0 foundations` with API, QA, artifact, and consumer verification in the body. Publication requires explicit authorization and must be monitored to completion.
