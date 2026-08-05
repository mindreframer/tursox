# EPIC007 Plan: Multiprocess Access and Compatibility Release

## Progress

- [x] Phase 7.1: Build deterministic child-process fixtures and platform preflight.
- [x] Phase 7.2: Test cross-process reads, writes, snapshots, and writer serialization.
- [x] Phase 7.3: Test checkpoints, schema changes, process failure, recovery, and integrity.
- [x] Phase 7.4: Test mode mixing, memory/MVCC rejection, filesystems, and sidecars.
- [x] Phase 7.5: Consolidate the generated Roadmap 2 capability and regression report.
- [ ] Phase 7.6: Synchronize `0.2.0`, docs, changelog, packages, and precompiled artifacts.
- [ ] Phase 7.7: Pass final QA/release verification and commit Epic 7.

## Implementation Steps

1. Add repository-owned child commands with barriers, timeouts, and cleanup.
2. Run readers/writers in genuinely separate OS processes.
3. Kill participants at controlled points and verify recovery/reopen.
4. Assert documented incompatibilities and classify unsupported platforms explicitly.
5. Ensure every Roadmap 2 capability status is backed by a named test/probe.
6. Keep `turso = 0.7.2`; update only Tursox release metadata and rebuilt artifacts.
7. Run full QA and release pipeline, monitor all targets, then commit.

## Quality Gate

- [x] Supported-platform multiprocess scenarios pass with real processes.
- [x] Failure/recovery leaves no corruption or orphan child processes.
- [x] Unsupported combinations fail clearly.
- [x] Capability report and executable probes agree.
- [ ] `0.2.0` artifacts pass source and no-Rust consumer smokes.
- [ ] Final QA passes.

## Commit Rule

Commit as `roadmap002 - epic 7 - release capability-verified Tursox 0.2.0`.
