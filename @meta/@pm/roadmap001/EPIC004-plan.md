# EPIC004 Plan: Transactions and MVCC

## Required Reading

Read `@meta/@pm/ROADMAP001.md`, `REFERENCES.md`, and `EPIC004-spec.md` completely before Phase 4.1; finding F5 governs concurrent mode on stable `0.7.2`.

## Progress

- [ ] Phase 4.1: Define transaction ownership, nesting, failure, and retry contracts.
- [ ] Phase 4.2: Implement deferred, immediate, exclusive, concurrent begin/commit/rollback paths.
- [ ] Phase 4.3: Add explicit WAL/MVCC journal configuration and compatibility validation.
- [ ] Phase 4.4: Preserve busy-snapshot classification and add bounded whole-transaction retries.
- [ ] Phase 4.5: Expose and verify supported MVCC checkpoint controls.
- [ ] Phase 4.6: Prove concurrent writes, conflicts, snapshots, rollback, integrity, and durability.
- [ ] Phase 4.7: Pass the epic gate and create the focused Epic 4 commit.

## Implementation Steps

1. Add low-level transaction operations and a rollback-safe callback wrapper.
2. Map deferred/immediate/exclusive through R1's stable API; implement concurrent through tested `BEGIN CONCURRENT` SQL per finding F5 unless the pinned crate is explicitly revised. Reject unsafe nesting and prevent same-connection interleaving in managed usage.
3. Set and verify journal mode using runtime probes; validate incompatible builder/connection options.
4. Expand native error classification and implement finite callback-level retry policy.
5. Add version-gated checkpoint threshold/passive/manual operations with documented result shapes.
6. Build deterministic barrier-based MVCC and mixed-mode tests, including reopen and integrity checks.
7. Run `bin/qa_check.sh` and commit the green epic.

## Quality Gate

- [ ] All callback failure paths roll back.
- [ ] Disjoint concurrent writers commit from separate connections.
- [ ] Same-row conflict is stable and retryable without partial commit.
- [ ] Retry bounds and non-retry classes are enforced.
- [ ] Checkpoint and reopen tests pass.
- [ ] MVCC experimental limitations are documented.
- [ ] QA passes.

## Commit Rule

Commit as `roadmap001 - epic 4 - add transactions and MVCC` with concurrency, conflict, retry, and durability verification in the body.
