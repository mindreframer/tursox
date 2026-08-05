# EPIC004 Spec: STRICT Tables, Custom Types, and Domains

## Purpose

Verify Turso's extended type system through Tursox while preserving the binding's five-value transport contract.

## References

- <https://docs.turso.tech/sql-reference/data-types>
- <https://docs.turso.tech/sql-reference/statements/create-domain>

## Scope

In scope:

- affinity and STRICT enforcement
- built-in custom types exposed by the pinned engine
- `CREATE TYPE` encode/decode, defaults, validation, and operators where available
- arrays, STRUCT, and UNION availability and round trips where available
- `CREATE DOMAIN`, defaults, not-null/check constraints, chaining, casts, updates, and drop restrictions
- `PRAGMA list_types` and type catalog introspection
- direct, prepared, transaction, persistence, and multi-connection behavior
- precise unsupported/partial classifications for documentation newer than the pin

Out of scope:

- automatic Elixir Date/Time/Decimal conversion
- hiding encoded storage classes behind new Tursox value types
- emulating absent type features

## Type Contract

Tursox transports the values returned by Turso as null, integer, real, text, or blob. Custom semantic interpretation remains explicit. Tests must separately prove logical decoded values, storage behavior where observable, constraints, ordering, indexes, and reopen behavior.

## Acceptance Criteria

- STRICT tables accept valid values and reject invalid storage classes.
- Every built-in/custom type advertised for `0.7.2` has a round-trip result.
- Encode/decode and domain constraints apply on insert, update, and cast where supported.
- Transaction rollback and reopen preserve correct type behavior.
- Type introspection reports expected definitions.
- In-use types/domains cannot be dropped incorrectly.
- Arrays/composites are either tested or explicitly classified unavailable.

## Test Strategy

Use feature-on/off databases, boundary and malformed values, prepared parameters, ordered queries, transaction rollback, reopen, schema introspection, and isolated probes for experimental failures.
