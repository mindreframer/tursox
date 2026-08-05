# Turso 0.7.2 executable capability report

This report is the Roadmap 2 compatibility baseline for Tursox 0.2.0. It records
behavior observed through public Elixir APIs against the exactly pinned
`turso = 0.7.2`; current web documentation is a checklist, not the authority.
Statuses are `supported`, `partial`, `unsupported`, `platform_limited`, or
`unsafe`. Named ExUnit files are the executable source of each claim.

## Core SQL

Proof: `test/core_sql_regression_test.exs` plus the focused statement,
transaction, pool, and manager suites.

| Capability | Status | Applicability and observed contract |
|---|---|---|
| DDL and schema changes | supported | File/memory, direct; tables, indexes and `ALTER TABLE ADD COLUMN` |
| CRUD, UPSERT and RETURNING | supported | Bound DML on file/memory; RETURNING rows must use the query/cursor API |
| Five storage classes | supported | Null, signed 64-bit integer, IEEE real, UTF-8 text and tagged blob round-trip |
| Expressions and relational queries | supported | Ordered joins, grouping, HAVING, subqueries, UNION and scalar expressions |
| Constraints | supported | Primary key, unique, check, not-null and opt-in foreign keys; stable `:constraint` errors |
| Prepared statements | supported | Positional/named values, reset/reuse, one active bounded cursor |
| Transactions and visibility | supported | Uncommitted writes are hidden; commit becomes visible; rollback is atomic |
| File persistence | supported | Committed data survives reopen, rolled-back data does not; integrity is `ok` |
| Shared in-memory database | supported | Connections derived from one database share state; independent opens do not |
| Pool and manager parity | supported | Representative ordered create/insert/query behavior uses the same database model |

The suite deliberately does not claim exhaustive SQLite conformance. SQL errors
are classified without depending on unstable engine prose, and every fixture
closes its native resources back to a measured baseline.
