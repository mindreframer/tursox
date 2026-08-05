# EPIC001 Plan: Native Foundation and Reproducible QA

## Required Reading

Read `@meta/@pm/ROADMAP001.md`, `REFERENCES.md`, and `EPIC001-spec.md` completely before Phase 1.1.

## Progress

- [x] Phase 1.1: Define and document direct, pooled, and managed public module boundaries.
- [x] Phase 1.2: Pin the stable Turso/Rustler stack and Rust toolchain with committed lockfiles.
- [x] Phase 1.3: Bootstrap `native/tursox_nif` and source-build NIF loading.
- [x] Phase 1.4: Implement panic containment, stable base errors, and resource accounting smoke calls.
- [x] Phase 1.5: Establish runtime, dirty scheduling, locking, logical-close, and secret-handling rules.
- [x] Phase 1.6: Create test support, CI, package skeleton, and authoritative `bin/qa_check.sh`.
- [x] Phase 1.7: Pass the epic gate and create the focused Epic 1 commit.

## Implementation Steps

1. Read `@meta/@pm/roadmap001/REFERENCES.md`; replace hello-world concepts with documented module contracts and non-goals.
2. Verify R1 `turso = 0.7.2` against required APIs; pin all native dependencies/toolchain and create the capability record required by reference section 5.
3. Add RustlerPrecompiled source-build configuration using R5's exact listed files as structural examples, without copying names/checksums or requiring the R5 checkout.
4. Add smoke success, structured error, contained panic, and resource-snapshot calls.
5. Record an ADR for runtime/scheduler/resource ownership and a versioned Turso capability matrix.
6. Extend QA with locked Mix/Cargo dependencies, format, compile warnings, Clippy, Rust tests, ExUnit, and CI.
7. Run `bin/qa_check.sh`, review the diff, then commit only the completed epic.

## Quality Gate

- [x] Source-built NIF loads from a clean checkout.
- [x] Smoke, error, panic, and resource lifecycle tests pass.
- [x] No sibling checkout or path dependency is required.
- [x] QA is executable, fail-fast, non-interactive, and green.
- [x] No database behavior was introduced.

## Commit Rule

Commit as `roadmap001 - epic 1 - establish native foundation and QA` with a body summarizing pins, runtime decisions, boundary tests, and `bin/qa_check.sh` verification.
