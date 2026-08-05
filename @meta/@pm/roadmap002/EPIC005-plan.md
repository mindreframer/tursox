# EPIC005 Plan: Views and Advanced Schema Features

## Progress

- [ ] Phase 5.1: Test ordinary view creation, querying, introspection, and drop behavior.
- [ ] Phase 5.2: Test materialized-view definitions and supported query shapes.
- [ ] Phase 5.3: Verify incremental maintenance across DML, commit, rollback, and reopen.
- [ ] Phase 5.4: Test generated columns, triggers, and `WITHOUT ROWID` tables.
- [ ] Phase 5.5: Test attach/detach ownership, isolation, and persistence.
- [ ] Phase 5.6: Test vacuum/autovacuum, dependency failures, and integrity.
- [ ] Phase 5.7: Publish schema capabilities, pass QA, and commit Epic 5.

## Implementation Steps

1. Cover standard views before experimental materialized behavior.
2. Probe aggregates, filters, unsupported functions, and view dependencies.
3. Use explicit transactions to prove atomic materialized maintenance.
4. Exercise advanced table/schema forms with introspection and reopen.
5. Use unique attached files and verify cleanup/isolation.
6. Record vacuum support and verify databases remain integral.
7. Update docs, run `bin/qa_check.sh`, and commit.

## Quality Gate

- [ ] Supported views have complete create/use/drop coverage.
- [ ] Materialized results never diverge from committed base data.
- [ ] Advanced schema features have executable statuses.
- [ ] Reopen and integrity checks pass.
- [ ] QA passes.

## Commit Rule

Commit as `roadmap002 - epic 5 - verify advanced schema features`.
