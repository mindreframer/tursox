# EPIC003 Plan: Experimental Feature Capability Matrix

## Progress

- [ ] Phase 3.1: Map documented flags to exact pinned Builder and Cargo capabilities.
- [ ] Phase 3.2: Align public feature names, validation, metadata, and disabled behavior.
- [ ] Phase 3.3: Probe views, types, index methods, generated columns, and rowid options.
- [ ] Phase 3.4: Probe encryption, vacuum/autovacuum, attach, and trigger availability.
- [ ] Phase 3.5: Probe multiprocess and MVCC checkpoint switches safely.
- [ ] Phase 3.6: Generate and verify supported/partial/unsupported/platform/unsafe statuses.
- [ ] Phase 3.7: Publish the feature matrix, pass QA, and commit Epic 3.

## Implementation Steps

1. Inspect only the exact locked crate/build when mapping switches.
2. Expose missing public options only when supported and safely configurable.
3. Add minimal feature-off/feature-on SQL probes for schema features.
4. Verify remaining documented switches without emulating absent functionality.
5. Isolate platform-specific or crash-risk probes.
6. Make tests and capability documentation detect matrix drift.
7. Run `bin/qa_check.sh` and commit.

## Quality Gate

- [ ] Every documented experimental feature has one explicit status.
- [ ] Public feature options match supported Builder switches.
- [ ] Disabled and incompatible behavior is tested.
- [ ] No feature claim depends only on current web documentation.
- [ ] QA passes.

## Commit Rule

Commit as `roadmap002 - epic 3 - publish experimental feature capabilities`.
