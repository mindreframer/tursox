# EPIC004 Plan: STRICT Tables, Custom Types, and Domains

## Progress

- [x] Phase 4.1: Test affinity, STRICT enforcement, and feature gating.
- [x] Phase 4.2: Inventory and round-trip built-in custom types available on the pin.
- [x] Phase 4.3: Test user-defined type encoding, decoding, defaults, and operators.
- [x] Phase 4.4: Test arrays, STRUCT, and UNION support or classify their absence.
- [x] Phase 4.5: Test domains, chained constraints, casts, updates, and drop rules.
- [x] Phase 4.6: Verify introspection, transactions, indexes, connections, and reopen.
- [x] Phase 4.7: Publish type capabilities, pass QA, and commit Epic 4.

## Implementation Steps

1. Establish ordinary/STRICT comparison cases with valid and invalid values.
2. Drive every available built-in type through bound writes and ordered reads.
3. Exercise `CREATE TYPE` semantics supported by `0.7.2`.
4. Probe composite and array syntax without assuming newer docs match the pin.
5. Exercise complete domain lifecycle and validation paths.
6. Verify catalogs, rollback, ordering/indexing, multi-connection use, and durability.
7. Update docs, run `bin/qa_check.sh`, and commit.

## Quality Gate

- [x] STRICT and custom-type gating is deterministic.
- [x] Supported logical types round-trip through Tursox values.
- [x] Type/domain constraints reject invalid writes atomically.
- [x] Unsupported newer syntax is classified explicitly.
- [x] QA passes.

## Commit Rule

Commit as `roadmap002 - epic 4 - verify custom types and domains`.
