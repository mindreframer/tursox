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

## Experimental feature switches

Proof: `test/experimental_capability_test.exs` and the disposable
`bin/capability_probe.exs`. The machine-readable authority is
`Tursox.Capabilities.experimental_features/0`; a drift test aligns every exposed
option with `Database.builder_features/0`.

| Documented feature | Rust builder / Tursox option | Status | Disabled/enabled finding |
|---|---|---|---|
| Views | always on / none | supported | Ordinary create/query/drop works without a flag |
| Materialized views | `experimental_materialized_views` / `:materialized_views` | unsafe | Disabled parser gate is stable; enabled 0.7.2 execution can bus-error and is probed only in a child BEAM |
| Custom types and domains | `experimental_custom_types` / `:custom_types` | unsafe | Disabled parser gate is stable; enabled create-type execution can bus-error and is child-only |
| Encryption | `experimental_encryption` / none | unsupported | Builder exists, but the disabled Cargo crypto feature and absent secret-safe open contract make exposure unsafe |
| Index methods | `experimental_index_method` / `:index_method` | partial | Parser gate works; method availability additionally depends on the deliberate Cargo `fts` feature |
| Autovacuum | absent / none | unsupported | Web-documented experimental builder switch is absent from 0.7.2 |
| Vacuum | `experimental_vacuum` / `:vacuum` | partial | Works on an initialized file; empty databases produce a 0.7.2 internal error |
| Attach/detach | `experimental_attach` / `:attach` | supported | Disabled gate and enabled attach/list/detach pass |
| Generated columns | `experimental_generated_columns` / `:generated_columns` | supported | Disabled gate and virtual generated result pass |
| `WITHOUT ROWID` | `experimental_without_rowid` / `:without_rowid` | supported | Disabled gate and enabled create pass |
| Multiprocess WAL | `experimental_multiprocess_wal` / `:multiprocess_wal` | platform_limited | Rejected with MVCC; real-process/platform results are in the release section |
| MVCC passive checkpoint | `experimental_mvcc_passive_checkpoint` / none | unsafe | Rejected before allocation; manual MVCC checkpoint is contained in a child BEAM |
| Triggers | compatibility no-op / none | supported | Always enabled in 0.7.2 |
| STRICT | compatibility no-op / none | supported | Always enabled in 0.7.2 |

No unavailable feature is emulated and no experimental result is a production
stability promise.
