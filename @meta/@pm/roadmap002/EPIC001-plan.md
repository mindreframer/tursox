# EPIC001 Plan: Core SQL and Database Regression Suite

## Progress

- [ ] Phase 1.1: Define the core SQL behavior matrix and shared assertion fixtures.
- [ ] Phase 1.2: Cover DDL, CRUD, values, expressions, joins, grouping, and compound queries.
- [ ] Phase 1.3: Cover constraints, foreign keys, errors, and failure atomicity.
- [ ] Phase 1.4: Cover prepared statements, bindings, cursor chunks, reset, and batches.
- [ ] Phase 1.5: Cover transactions, connection visibility, persistence, and reopen.
- [ ] Phase 1.6: Run representative behavior through pools/managers and audit resource cleanup.
- [ ] Phase 1.7: Publish the baseline, pass QA, and commit Epic 1.

## Implementation Steps

1. Build reusable file/memory fixtures without creating a speculative conformance framework.
2. Add table-driven tests for common SQL forms and exact ordered results.
3. Assert stable Tursox errors and no partial writes after failed constraints/statements.
4. Exercise real prepared resources and bounded cursors with all parameter/value classes.
5. Use multiple derived connections and reopen checks for visibility and durability.
6. Add focused pool/manager parity cases and resource baselines.
7. Update capability documentation, run `bin/qa_check.sh`, and commit.

## Quality Gate

- [ ] Core file and memory suites pass.
- [ ] Commit, rollback, and reopen behavior is deterministic.
- [ ] Direct, pool, and manager smoke behavior agrees.
- [ ] Failures leave no leaked resources or partial writes.
- [ ] QA passes.

## Commit Rule

Commit as `roadmap002 - epic 1 - establish core SQL regression baseline`.
