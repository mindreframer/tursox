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

## PRAGMAs

Proof: `test/pragma_capability_test.exs`. `Connection.pragma_query/3` safely
renders `{:identifier, name}`, non-negative integer, and quoted string arguments;
raw SQL fragments are not accepted. Settings are direct-connection operations;
pools can issue generic SQL when checkout-scoped policy is intentional.

| Family / names | Status | Observed 0.7.2 behavior |
|---|---|---|
| Metadata: `database_list`, `page_count`, `page_size`, `max_page_count`, `freelist_count`, `encoding`, `schema_version`, `application_id`, `user_version` | supported | Ordered scalar rows; application/user versions persist; page size is configurable before schema creation |
| Schema: `table_info`, `table_xinfo`, `table_list`, `index_list`, `index_info`, `index_xinfo` | supported | Documented 6/7/6/5/3/6-column shapes; quoted hostile identifiers cannot inject SQL |
| `function_list` | supported | Six columns and runtime function inventory |
| `pragma_list` | partial | Returns one-column inventory but 0.7.2 omits `pragma_list` itself |
| `journal_mode` | supported | WAL and opt-in MVCC are configured and read back during database open |
| `cache_size`, `cache_spill`, `synchronous`, `temp_store`, `busy_timeout` | supported | Query/update scalar shapes; connection-local |
| `query_only`, `foreign_keys`, `ignore_check_constraints` | supported | Connection-local and enforcement tested; query-only write is classified `:misuse` by 0.7.2 |
| `data_sync_retry`, `require_where`, `i_am_a_dummy` | supported | Connection-local query/update; unqualified update/delete rejection tested for `require_where` |
| `integrity_check`, `integrity_check(N)`, `quick_check` | supported | Representative WAL workload returns exactly `[["ok"]]` |
| `wal_checkpoint` | supported | WAL returns one `[busy, log_frames, checkpointed_frames]` integer row |
| `mvcc_checkpoint_threshold`, `mvcc_gc_threshold` | supported | MVCC-only non-negative query/update; WAL access errors |
| `capture_data_changes_conn` | unsupported | Documented argument is accepted but returns no rows and creates no capture behavior on this pin |
| `cipher`, `hexkey` | unsupported | Encryption is not enabled or exposed; empty/inert query results are not capability |
| `list_types` | partial | Base inventory is available; custom-type depth is recorded below |
| `legacy_file_format` | unsupported | Accepted as an unknown/compatibility pragma and returns no rows |

Potentially crash-prone passive MVCC checkpointing remains `unsafe`: it is not
in the public feature allowlist and is never run in the main ExUnit VM. Secret
keys are not exposed as Tursox options, telemetry metadata, or inspect data.
