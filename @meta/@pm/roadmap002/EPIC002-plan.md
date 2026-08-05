# EPIC002 Plan: PRAGMA Coverage and Introspection

## Progress

- [x] Phase 2.1: Inventory documented PRAGMAs and define expected capability statuses.
- [x] Phase 2.2: Test database metadata and schema/index/function introspection.
- [x] Phase 2.3: Add safe argument-bearing PRAGMA support and injection tests.
- [x] Phase 2.4: Test configuration scope, validation, and persistence.
- [x] Phase 2.5: Test integrity, WAL/MVCC, CDC, encryption, and type PRAGMAs.
- [x] Phase 2.6: Isolate hazardous probes and document unsupported/result-shape findings.
- [x] Phase 2.7: Publish the PRAGMA matrix, pass QA, and commit Epic 2.

## Implementation Steps

1. Map each documentation entry to a direct test or explicit unsupported probe.
2. Assert ordered columns/rows for metadata and introspection.
3. Extend the least API needed for safely quoted table/index arguments.
4. Test connection-local versus persistent settings across connections and reopen.
5. Exercise journal- and feature-gated PRAGMAs with appropriate fixtures.
6. Run crash-risk operations in disposable processes and record exact outcomes.
7. Update docs, run `bin/qa_check.sh`, and commit.

## Quality Gate

- [x] Every checklist PRAGMA has an executable status.
- [x] Supported result shapes and scopes are asserted.
- [x] Identifier/argument handling is injection-safe.
- [x] Hazardous probes cannot crash the main test VM.
- [x] QA passes.

## Commit Rule

Commit as `roadmap002 - epic 2 - verify PRAGMA and introspection behavior`.
