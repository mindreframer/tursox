# EPIC001 Plan: Native Foundation and Reproducible QA

## Progress

- [ ] Phase 1.1: Define and document direct, pooled, and managed public module boundaries.
- [ ] Phase 1.2: Pin the stable Turso/Rustler stack and Rust toolchain with committed lockfiles.
- [ ] Phase 1.3: Bootstrap `native/tursox_nif` and source-build NIF loading.
- [ ] Phase 1.4: Implement panic containment, stable base errors, and resource accounting smoke calls.
- [ ] Phase 1.5: Establish runtime, dirty scheduling, locking, logical-close, and secret-handling rules.
- [ ] Phase 1.6: Create test support, CI, package skeleton, and authoritative `bin/qa_check.sh`.
- [ ] Phase 1.7: Pass the epic gate and create the focused Epic 1 commit.

## Implementation Steps

1. Replace hello-world concepts with documented module contracts and non-goals.
2. Verify `turso = 0.7.2` against required APIs; pin all native dependencies and a supported Rust toolchain.
3. Add RustlerPrecompiled source-build configuration modeled on Parquex, without checksum artifacts yet.
4. Add smoke success, structured error, contained panic, and resource-snapshot calls.
5. Record an ADR for runtime/scheduler/resource ownership and a versioned Turso capability matrix.
6. Extend QA with locked Mix/Cargo dependencies, format, compile warnings, Clippy, Rust tests, ExUnit, and CI.
7. Run `bin/qa_check.sh`, review the diff, then commit only the completed epic.

## Quality Gate

- [ ] Source-built NIF loads from a clean checkout.
- [ ] Smoke, error, panic, and resource lifecycle tests pass.
- [ ] No sibling checkout or path dependency is required.
- [ ] QA is executable, fail-fast, non-interactive, and green.
- [ ] No database behavior was introduced.

## Commit Rule

Commit as `roadmap001 - epic 1 - establish native foundation and QA` with a body summarizing pins, runtime decisions, boundary tests, and `bin/qa_check.sh` verification.
