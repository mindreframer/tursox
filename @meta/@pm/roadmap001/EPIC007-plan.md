# EPIC007 Plan: Hardening, Documentation, and Initial Release

## Progress

- [ ] Phase 7.1: Stabilize names, options, defaults, errors, result shapes, and compatibility guarantees.
- [ ] Phase 7.2: Add safe telemetry and resource/scheduler observability.
- [ ] Phase 7.3: Harden fault, contention, large-result, churn, and shutdown paths.
- [ ] Phase 7.4: Complete README, API guides, architecture, compatibility, security, and changelog docs.
- [ ] Phase 7.5: Add package audits, CI matrix, precompiled build, raw smoke, and no-Rust consumers.
- [ ] Phase 7.6: Synchronize `0.1.0`, validate exact artifacts/checksums, and audit clean installs.
- [ ] Phase 7.7: Pass final QA, publish/verify when authorized, and create the focused Epic 7 commit.

## Implementation Steps

1. Freeze the initial API after a direct/pool/manager consistency review and mark experimental surfaces.
2. Emit redacted telemetry and expose deterministic resource gauges for operations and tests.
3. Run bounded-memory, scheduler responsiveness, high-cardinality, failure, and lifecycle suites.
4. Test every documented example and publish an exact Turso/SQLite capability matrix.
5. Mirror Parquex's pinned CI/release design, adapting artifact names and Turso native dependencies.
6. Audit the unpacked Hex package and every precompiled consumer with Rust hidden; synchronize release metadata.
7. Run full QA and release verification, then commit only when all advertised artifacts are proven.

## Quality Gate

- [ ] API/docs/compatibility review is complete.
- [ ] Telemetry and error redaction tests pass.
- [ ] Memory, scheduler, churn, and fault suites pass.
- [ ] Hex package and docs build cleanly.
- [ ] Exact binary set passes raw and no-Rust consumer smoke tests.
- [ ] Version and changelog are synchronized.
- [ ] Final `bin/qa_check.sh` passes from a clean checkout.

## Commit Rule

Commit as `roadmap001 - epic 7 - release Tursox 0.1.0 foundations` with API, QA, package, artifact, and consumer verification in the body. Publication requires explicit authorization and must be monitored to completion.
