# EPIC006 Plan: Full-Text Search and Extensions

## Progress

- [ ] Phase 6.1: Select and document pinned Cargo features needed for FTS/extensions.
- [ ] Phase 6.2: Test FTS indexes, tokenizers, weights, matching, and query syntax.
- [ ] Phase 6.3: Test scoring, highlighting, bounded results, and invalid queries.
- [ ] Phase 6.4: Test FTS DML, transactions, optimize, drop, and reopen behavior.
- [ ] Phase 6.5: Inventory built-in/loadable extension functions in the embedded build.
- [ ] Phase 6.6: Smoke-test available extension families and source/precompiled parity.
- [ ] Phase 6.7: Publish extension capabilities, pass QA, and commit Epic 6.

## Implementation Steps

1. Enable only deliberate native features and audit build/artifact effects.
2. Resolve documented FTS syntax against executable `0.7.2` behavior.
3. Assert deterministic matches, return types, ranking, and highlighting.
4. Verify index maintenance, transaction visibility, durability, and cleanup.
5. Derive the extension inventory from runtime function/loading probes.
6. Add representative valid/invalid cases for each available family and target smokes.
7. Update docs, run `bin/qa_check.sh`, and commit.

## Quality Gate

- [ ] Advertised FTS behavior passes end to end.
- [ ] FTS lifecycle and transaction limitations are documented.
- [ ] Extension inventory matches runtime availability.
- [ ] Source and precompiled consumers expose the same capabilities.
- [ ] QA passes.

## Commit Rule

Commit as `roadmap002 - epic 6 - add tested FTS and extension coverage`.
