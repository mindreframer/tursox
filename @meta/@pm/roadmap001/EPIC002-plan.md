# EPIC002 Plan: Database and Connection Resources

## Required Reading

Read `@meta/@pm/ROADMAP001.md`, `REFERENCES.md`, and `EPIC002-spec.md` completely before Phase 2.1.

## Progress

- [ ] Phase 2.1: Define validated database paths, open modes, builder options, and opaque Elixir handles.
- [ ] Phase 2.2: Implement native database resources with logical close and ancestry accounting.
- [ ] Phase 2.3: Implement multiple native connections derived from one database resource.
- [ ] Phase 2.4: Add connection settings, status, cache flush, and supported pragma primitives.
- [ ] Phase 2.5: Prove file persistence and shared-versus-isolated in-memory semantics.
- [ ] Phase 2.6: Harden close ordering, invalid options, path failures, and high database counts.
- [ ] Phase 2.7: Pass the epic gate and create the focused Epic 2 commit.

## Implementation Steps

1. Add `Tursox.Database`, `Tursox.Connection`, option validators, and opaque inspections.
2. Map selected Turso builders without hidden feature defaults; preserve parent resources in children.
3. Derive every connection using `Database::connect`, never by reopening a path.
4. Expose busy timeout and only confirmed stable connection metadata/maintenance calls.
5. Add temporary file, memory-sharing, isolation, persistence, and resource-counter tests.
6. Stress many open databases/connections and every close ordering; document limitations.
7. Run `bin/qa_check.sh` and commit the green epic.

## Quality Gate

- [ ] One native database resource backs all of its derived connections.
- [ ] In-memory sharing and database isolation tests pass.
- [ ] Resource counters return to baseline after every lifecycle test.
- [ ] Unsupported builder behavior is rejected rather than ignored.
- [ ] QA passes.

## Commit Rule

Commit as `roadmap001 - epic 2 - add database and connection resources` with lifecycle and multi-database verification in the body.
