# EPIC005 Plan: Shared-Handle DBConnection Pool

## Required Reading

Read `@meta/@pm/ROADMAP001.md`, `REFERENCES.md`, and `EPIC005-spec.md` completely before Phase 5.1; inspect the exact locked DBConnection version per R7.

## Progress

- [x] Phase 5.1: Define pool ownership, query/result, and DBConnection compatibility contracts.
- [x] Phase 5.2: Start one database owner and derive every pool worker connection from it.
- [x] Phase 5.3: Implement prepare/execute/close, status, ping, and stable disconnect classification.
- [x] Phase 5.4: Implement declare/fetch/deallocate with bounded native cursor chunks.
- [x] Phase 5.5: Implement all transaction modes and checkout-safe rollback behavior.
- [x] Phase 5.6: Harden worker restart, in-memory sharing, shutdown, early halt, and resource counts.
- [x] Phase 5.7: Pass the epic gate and create the focused Epic 5 commit.

## Implementation Steps

1. Read R7 version-matched docs/source, then add `Tursox.Query`, `Tursox.Result`, and the DBConnection protocol implementation using its exact callback tuples.
2. Use R3 only as a cautionary/design reference; build a database-owner/pool lifecycle that passes one R1 database resource to every worker.
3. Map DBConnection callbacks to the direct native resources and stable errors.
4. Back cursor callbacks with bounded fetch and deterministic deallocation.
5. Forward transaction modes and verify checkout exclusivity.
6. Add pool lifecycle/failure tests proving one database resource and no leaks.
7. Run `bin/qa_check.sh` and commit the green epic.

## Quality Gate

- [x] `pool_size: N` creates one database and N derived connections.
- [x] In-memory pool workers share state.
- [x] Streams are bounded and clean up on halt.
- [x] Transaction and worker-replacement tests pass.
- [x] Direct API has no DBConnection startup requirement.
- [x] QA passes.

## Commit Rule

Commit as `roadmap001 - epic 5 - add shared-handle DBConnection pool` with resource-count, stream, and transaction verification in the body.
