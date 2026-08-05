# EPIC003 Plan: Prepared Statements and Bounded Row Cursors

## Required Reading

Read `@meta/@pm/ROADMAP001.md`, `REFERENCES.md`, and `EPIC003-spec.md` completely before Phase 3.1.

## Progress

- [x] Phase 3.1: Define stable value, parameter, column, row, and result contracts.
- [x] Phase 3.2: Implement strict positional/named parameter decoding and value encoding.
- [x] Phase 3.3: Implement execute, execute-batch, and real prepared statement resources.
- [x] Phase 3.4: Implement native row cursors with bounded fetch and ordered metadata.
- [x] Phase 3.5: Add reset/reuse, explicit close, lazy enumeration, and conversion helpers.
- [x] Phase 3.6: Verify memory bounds, early halt, duplicate columns, misuse, and cleanup.
- [x] Phase 3.7: Pass the epic gate and create the focused Epic 3 commit.

## Implementation Steps

1. Add value/parameter normalization and `%Tursox.Result{}` without row maps by default.
2. Decode positional lists and named maps/lists into Turso params with precise validation errors.
3. Wrap `Connection::prepare`, `Statement::execute`, reset, and metadata in tracked resources.
4. Store `Rows` in a cursor resource and fetch at most `max_rows` per dirty call.
5. Add Stream/Enumerable cleanup and explicit limited materialization/map helpers.
6. Test cardinality much larger than fetch size and deterministic resource release on every exit path.
7. Run `bin/qa_check.sh` and commit the green epic.

## Quality Gate

- [x] Value and named/positional parameter suites pass.
- [x] Prepared statements are real native resources and reusable after reset.
- [x] Fetch size bounds every returned chunk.
- [x] Early halt leaves no cursor or active-statement lease.
- [x] Ordered duplicate columns are preserved.
- [x] QA passes.

## Commit Rule

Commit as `roadmap001 - epic 3 - add prepared statements and bounded cursors` with query-boundary and lifecycle verification in the body.
