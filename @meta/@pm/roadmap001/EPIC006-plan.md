# EPIC006 Plan: Supervised Multi-Database Management

## Required Reading

Read `@meta/@pm/ROADMAP001.md`, `REFERENCES.md`, and `EPIC006-spec.md` completely before Phase 6.1.

## Progress

- [x] Phase 6.1: Define manager supervision, naming, tenant identity, ownership, and close contracts.
- [x] Phase 6.2: Implement isolated open/lookup/list state without dynamic atoms or a global singleton.
- [x] Phase 6.3: Start one owned database/pool entry per tenant with independent options.
- [x] Phase 6.4: Add atomic duplicate/path checks and `max_databases` admission control.
- [x] Phase 6.5: Implement graceful drain, force-close bounds, entry restart, and manager shutdown.
- [x] Phase 6.6: Stress many mixed-mode databases, races, crashes, isolation, and resource cleanup.
- [x] Phase 6.7: Pass the epic gate and create the focused Epic 6 commit.

## Implementation Steps

1. Add a caller-supervised manager with pid/name addressing and safe tenant IDs.
2. Keep metadata in manager state or a private registry owned by that manager; do not create atoms.
3. Start each tenant entry with one database owner and shared-handle pool.
4. Serialize open decisions and canonical path/capacity validation before native allocation.
5. Drain and close entries predictably; document persistent versus memory restart semantics.
6. Add race and high-cardinality tests with mixed MVCC/WAL settings and exact resource counts.
7. Run `bin/qa_check.sh` and commit the green epic.

## Quality Gate

- [x] Multiple independent managers and overlapping IDs work.
- [x] Duplicate/capacity races leak no resources.
- [x] Tenant configuration and data remain isolated.
- [x] Close/restart/shutdown behavior is deterministic.
- [x] No dynamic atoms or global manager are introduced.
- [x] QA passes.

## Commit Rule

Commit as `roadmap001 - epic 6 - add supervised multi-database manager` with race, isolation, restart, and cleanup verification in the body.
