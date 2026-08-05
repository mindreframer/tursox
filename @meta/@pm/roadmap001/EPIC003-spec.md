# EPIC003 Spec: Prepared Statements and Bounded Row Cursors

## Purpose

Provide a real SQLite-like statement interface while preserving ordered results and bounded query transfer.

## Required References

Read `@meta/@pm/roadmap001/REFERENCES.md`, especially R1 `src/lib.rs`, `rows.rs`, `params.rs`, and `value.rs`; R4's low-level conventions; and findings F2 and F3.

## Scope

In scope:

- SQLite values: null, signed 64-bit integer, real, UTF-8 text, and blob
- booleans mapped explicitly to integer and blobs tagged as `{:blob, binary}`
- positional and named parameters with strict count/name/type validation
- connection execute, execute-batch, prepare, and query convenience calls
- native prepared statement and cursor resources
- statement reset/reuse, column names, declaration types, and affected rows
- cursor `fetch/2`, one-row stepping, explicit close, and lazy Enumerable convenience
- ordered row lists and explicit map conversion with a duplicate-column policy
- explicit bounded `all` convenience with caller limit

Out of scope:

- automatic Date/Time/custom type conversion
- implicit full result materialization
- transaction callbacks, pooling, and management
- user-defined functions/extensions

## Statement and Cursor Contract

A statement belongs to exactly one connection. Cross-connection use fails with `:misuse`. A statement cannot be reset or re-executed while one of its cursors is active. Cursor fetch returns no more than the requested number of rows and yields one of `{:rows, rows}`, `{:done, rows}`, or `:done` as finalized in implementation.

Closing or exhausting a cursor releases its active-statement lease. Early Enumerable halt closes the cursor. Closing a statement invalidates new queries but safely handles existing descendant state according to the tested resource contract.

Column names and rows remain ordered. Duplicate names are legal. Conversion to maps must require an explicit collision choice such as `:first`, `:last`, or `:error`.

## Acceptance Criteria

- All five SQLite storage classes round-trip, including empty and non-UTF-8 blobs.
- Positional and named parameters bind correctly; invalid values fail before execution where practical.
- Prepared statements can be reset and reused after completion.
- Duplicate columns and their order are preserved.
- A result much larger than fetch size is consumed in bounded chunks.
- Early halt and explicit close release cursor/statement resources.
- Execute-batch handles multiple statements and reports errors with safe context.
- No default query API builds maps or materializes all rows.

## Test Strategy

Cover parameter boundaries (`i64` min/max and overflow), UTF-8, blobs, null/boolean, named prefixes, duplicate/missing names, malformed SQL, zero rows, wide rows, huge rows, many chunks, early halt, statement busy state, reset, cross-connection misuse, and close ordering.
