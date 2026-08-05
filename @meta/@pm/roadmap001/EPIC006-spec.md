# EPIC006 Spec: Supervised Multi-Database Management

## Purpose

Offer an optional building block for services that keep many tenant databases open while preserving per-database isolation and caller-controlled policy.

## Required References

Read `@meta/@pm/roadmap001/REFERENCES.md`, especially the source-authority rules, findings F1 and F10, and R7 for pool ownership behavior. No sibling project defines the manager contract; this epic spec and ROADMAP001 are authoritative.

## Scope

In scope:

- `Tursox.Manager` as a supervised process/tree with caller-selected name
- explicit `open`, `lookup/fetch`, `list`, `close`, and `stop` operations
- arbitrary safe tenant IDs, isolated database/path/options/pool settings, and metadata without secrets
- atomic duplicate-ID handling and canonical-path conflict handling
- capacity limit and explicit admission failure
- per-entry restart behavior for persistent databases
- graceful drain/close and force-close timeout behavior
- telemetry hooks for manager lifecycle
- multiple independent managers in one VM

Out of scope:

- mandatory application-global Registry/DynamicSupervisor
- automatic idle/LRU eviction
- durable tenant catalog or auto-open after whole-manager restart
- network APIs, authentication, quotas, billing, or routing policy
- moving a live database between nodes

## Manager Contract

The manager is optional; direct resources and standalone pools remain public. No module-owned singleton is started by the Tursox application. Callers place one or more managers in their own supervision tree and address each by pid/name.

Tenant IDs are never converted to atoms. Open is atomic: concurrent opens for one ID produce one entry or a deterministic `:already_open` result. Different IDs cannot silently open the same canonical path with incompatible options. Every entry owns one database resource and its pool.

Capacity is explicit (`max_databases`) and checked before native open. Close removes the entry from lookup, rejects new work, drains within a configured bound, then releases resources. Listing exposes safe operational metadata but no SQL, params, rows, encryption keys, or auth data.

## Acceptance Criteria

- One manager opens and concurrently serves many isolated file and memory databases.
- Multiple managers can use overlapping tenant IDs without interference.
- Concurrent duplicate opens are atomic and leak-free.
- Capacity rejection opens no native resource.
- Closing one tenant does not affect others and returns counters to the expected level.
- Persistent entry crash/restart preserves data; memory restart semantics are documented.
- Manager shutdown drains all owned entries and resources.
- No tenant ID creates an atom.

## Test Strategy

Exercise 100+ tenant IDs, mixed WAL/MVCC options, concurrent open/close/lookup, duplicate paths, capacity races, process crashes, persistent reopen, manager restart, force-close, pool checkouts during close, and native/BEAM resource baselines.
