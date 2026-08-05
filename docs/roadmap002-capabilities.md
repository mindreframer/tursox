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
| Index methods | `experimental_index_method` / `:index_method` | supported | Parser gate works and every build deliberately includes the Cargo `fts` feature |
| Autovacuum | absent / none | unsupported | Web-documented experimental builder switch is absent from 0.7.2 |
| Vacuum | `experimental_vacuum` / `:vacuum` | partial | Works on an initialized file; empty databases produce a 0.7.2 internal error |
| Attach/detach | `experimental_attach` / `:attach` | supported | Disabled gate and enabled attach/list/detach pass |
| Generated columns | `experimental_generated_columns` / `:generated_columns` | unsafe | Disabled gate is stable; reading an enabled generated value can segfault and is probed only in a child BEAM |
| `WITHOUT ROWID` | `experimental_without_rowid` / `:without_rowid` | supported | Disabled gate and enabled create pass |
| Multiprocess WAL | `experimental_multiprocess_wal` / `:multiprocess_wal` | platform_limited | Rejected with MVCC; real-process/platform results are in the release section |
| MVCC passive checkpoint | `experimental_mvcc_passive_checkpoint` / none | unsafe | Rejected before allocation; manual MVCC checkpoint is contained in a child BEAM |
| Triggers | compatibility no-op / none | supported | Always enabled in 0.7.2 |
| STRICT | compatibility no-op / none | supported | Always enabled in 0.7.2 |

No unavailable feature is emulated and no experimental result is a production
stability promise.

## STRICT tables, custom types, and domains

Proof: `test/type_capability_test.exs`; enabled experimental probes use a fresh
child BEAM per type family.

| Type capability | Status | Observed contract |
|---|---|---|
| Ordinary affinity | supported | Numeric/text affinity conversions and deliberately flexible storage match ordered `typeof` results |
| STRICT base types | supported | `INTEGER`, `REAL`, `TEXT`, `BLOB`, and `ANY` accept convertible values and atomically reject incompatible storage classes |
| Prepared/transaction/index/reopen behavior | supported | Bound writes, constraint rollback, multiple connections, index planning, durability, and integrity pass |
| `PRAGMA list_types` | partial | Exactly six columns for five base rows; no custom definitions on the safe configuration |
| `sqlite_turso_types` | unsupported | Catalog virtual table documented by newer web docs is absent on 0.7.2 |
| Documented built-in semantic types | unsupported | `date`, `time`, `timestamp`, `varchar`, `numeric`, `smallint`, `boolean`, `uuid`, `bytea`, `inet`, `json`, and `jsonb` are absent from the pinned inventory |
| User-defined `CREATE TYPE` | unsafe | Disabled gate is stable; enabled encode/decode probe can terminate 0.7.2, so defaults/operators/drop cannot be advertised |
| Arrays | unsafe | Disabled gate is stable; enabled constructor/table probe is child-only |
| `STRUCT` and `UNION` | unsafe | Disabled gate is stable; enabled create probes are child-only |
| Domains | unsafe | Disabled gate is stable; enabled create/constraint probe is child-only, so chaining/casts/drop rules are not advertised |

Tursox still transports only the five engine storage classes. It does not infer
Elixir date, decimal, UUID, array, or composite values. Unsafe findings are valid
pin results rather than emulated features or weakened tests.

## Views and advanced schema

Proof: `test/view_capability_test.exs`, `test/table_feature_test.exs`, and
`test/storage_schema_test.exs`.

| Schema capability | Status | Observed contract |
|---|---|---|
| Ordinary views | supported | Filtered/aggregate views query and introspect as `view`; writes fail; drop leaves base data |
| Materialized views | unsafe | Disabled definitions fail without schema damage; enabled creation remains child-only, so no incremental-maintenance claim is made |
| Generated columns | supported | Virtual values and indexes track insert/update, rollback, sibling connections, and reopen |
| Triggers | supported | Always-on update trigger and audit effects commit/roll back atomically; schema introspection/drop pass |
| `WITHOUT ROWID` | supported | Primary key is mandatory, hidden `rowid` is absent, ordering and reopen pass |
| Attach/detach | supported | Opt-in file schema has isolated names/data, appears in `database_list`, persists independently, and detaches cleanly |
| Vacuum | partial | Opt-in `VACUUM` compacts initialized file databases while preserving rows/integrity; empty database error is a pin limitation |
| Autovacuum | unsupported | `PRAGMA auto_vacuum` has an empty result shape and updates demand a builder flag absent from public 0.7.2 |

Materialized-view IVM, unsupported query shapes, dependencies, and refresh are not
advertised because the enabled pin is unsafe. File fixtures use unique local
paths and close attached/database resources before cleanup.

## Full-text search

Proof: `test/fts_test.exs`; the no-Rust consumer smoke also creates and queries
an FTS index, enforcing source/precompiled parity. All builds use
`turso/default-features = false` plus only `features = ["fts"]`; the opt-in
`:index_method` database switch remains required.

| FTS capability | Status | Observed 0.7.2 behavior |
|---|---|---|
| Index and matching | supported | `CREATE INDEX ... USING fts(cols)` and `fts_match(cols, query)` return deterministic ordered IDs |
| Ranking | supported | `fts_score` returns real BM25-like scores with deterministic relative ordering |
| Highlighting | supported | `fts_highlight(cols, open, close, query)` returns text and preserves unmatched text |
| Query syntax | partial | Terms, boolean AND, and phrases pass; documented prefix behavior is not advertised on this pin |
| Tokenizers | partial | Global `raw`, `simple`, `whitespace`, and `ngram` options create; newer per-column `WITH tokenizer=...` syntax is rejected |
| Field weights | supported | Global `WITH (weights = 'column=weight,...')` creates and ranks |
| Bounded/bound query | supported | Parameters and incremental cursor chunks preserve limits and order |
| DML and transactions | supported | Insert/update/delete maintain the index; rollback removes index changes; unlike newer docs, 0.7.2 has read-your-writes on the writer |
| Optimize/drop/reopen | supported | Named optimize succeeds, index survives reopen, delete/drop cleanly remove indexed/schema state |
| Invalid queries/methods | supported | Stable Tursox errors without SQL/row leakage |

Turso FTS is Tantivy-backed and is not advertised as SQLite FTS5 compatibility.
The exact upstream `oneshot` 0.1.13 source is vendored only because Tantivy's
required crates.io index entry is unavailable; licenses and attribution ship in
the package.

## Built-in and loadable extensions

Proof: `test/extension_inventory_test.exs`, derived from `function_list` and
`module_list` rather than web-documentation presence.

| Extension family | Status | Pinned inventory / smoke |
|---|---|---|
| UUID | supported | UUID4/7, blob/string conversion; representative blob/text widths pass |
| Regexp | partial | `regexp` and `REGEXP` operator work; newer substring/capture/replace functions are absent |
| Vector | supported | vector32 extraction and L2 distance return blob-backed vector/text/real shapes |
| Time | supported | Opaque blob values, date formatting, and duration constants pass |
| Percentile | supported | median, percentile, continuous, and discrete aggregate shapes pass |
| `generate_series` | supported | Module yields inclusive ordered integer rows |
| Crypto | unsupported | No functions in the embedded registry |
| Fuzzy | unsupported | No functions in the embedded registry |
| IP address | unsupported | Documented family absent (an unrelated `validate_ipaddr` scalar exists) |
| CSV | unsupported | No CSV module; virtual table creation fails safely |
| Runtime loading | unsupported | `load_extension` is registered but runtime loading is disabled; names and arbitrary native paths fail safely |

Malformed UUID/regexp/percentile inputs return NULL on 0.7.2, and a zero series
step uses the default positive step; vector dimension and invalid time inputs
return errors. These tested differences are retained rather than normalized.
