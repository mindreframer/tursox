# EPIC006 Spec: Full-Text Search and Extensions

## Purpose

Make the useful FTS and extension capabilities present in the pinned embedded Turso build discoverable and tested through Tursox.

## References

- <https://docs.turso.tech/sql-reference/functions/fts>
- <https://docs.turso.tech/sql-reference/extensions>

## Scope

In scope:

- deliberate `turso` Cargo feature selection required for FTS
- FTS index creation, supported tokenizers/weights, matching, scoring, highlighting, and query syntax
- insert/update/delete, commit/rollback visibility, reopen, drop, and `OPTIMIZE INDEX`
- an inventory based on `PRAGMA function_list` and runtime loading behavior
- smoke and boundary tests for available UUID, regexp, vector, time, percentile, crypto, fuzzy, IP, CSV, and series functionality
- exact documentation of built-in, loadable, unavailable, and platform-limited extensions

Out of scope:

- arbitrary SQLite `.so`/`.dll` extensions
- user-defined Elixir/Rust SQL functions
- adding large dependencies solely to imitate unavailable extensions
- claiming compatibility with SQLite FTS5 syntax

## Extension Contract

The build must opt into native capabilities deliberately and document package-size/platform consequences. Dedicated FTS documentation and extension-summary syntax must be reconciled by tests against `0.7.2`; only the observed syntax is advertised. Extension errors must remain stable and must not leak raw data.

## Acceptance Criteria

- FTS support is intentionally enabled or precisely documented as impossible on the pin.
- Supported FTS syntax, tokenizers, ranking, highlighting, and maintenance pass end-to-end tests.
- FTS transaction visibility and reopen behavior are documented from tests.
- Available extension families have representative return-type and invalid-input tests.
- `function_list`/loading results agree with the published inventory.
- Unsupported extension loading fails safely.
- Precompiled and source builds expose the same advertised extension set.

## Test Strategy

Use deterministic corpora, exact expected matches, bounded result fetching, transactions, reopen, malformed queries, binary return values, temporary CSV files, function inventory snapshots, and target smoke tests.
