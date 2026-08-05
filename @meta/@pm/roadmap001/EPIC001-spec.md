# EPIC001 Spec: Native Foundation and Reproducible QA

## Purpose

Establish the Elixir/Rust boundary and one deterministic quality gate before database behavior is added.

## Required References

- `@meta/@pm/ROADMAP001.md`
- `@meta/@pm/roadmap001/REFERENCES.md`, especially R1, R3, R5, R6 and findings F1–F10
- R1 exact crate source is the dependency authority; R2–R5 are read-only design references and may be absent locally

## Scope

In scope:

- public module boundaries for database, connection, statement, cursor, result, error, pool, and manager layers
- exact stable pins for Rustler, RustlerPrecompiled, Turso, Tokio, Elixir dependencies, and Rust toolchain
- `native/tursox_nif` with a loadable smoke NIF
- runtime initialization, scheduler, mutex, panic, logical-close, and error-translation rules
- native success/error smoke calls and test-only resource accounting
- deterministic QA, CI, temporary-directory helpers, and package metadata skeleton
- a capability matrix tied to the selected Turso version

Out of scope:

- opening a Turso database
- SQL, parameters, statements, rows, transactions, MVCC behavior, pooling, or management
- precompiled release publication

## Foundation Contract

The native crate is self-contained and must not use path dependencies to sibling checkouts. Cargo dependencies and the Rust toolchain are exact and locked. Turso's default features must be reviewed deliberately; the NIF must not accidentally install an allocator or large optional feature without documentation.

Every NIF is panic-contained and returns one stable Elixir error shape. Work that can block or drive Turso I/O cannot run on a normal BEAM scheduler. The resource model supports deterministic logical close and test-only counters before production resources are added.

## Acceptance Criteria

- `mix test` compiles and loads a NIF from source.
- Public smoke success and translated-error tests cross the NIF boundary.
- Native panic handling is tested without crashing the VM.
- Dependency and toolchain versions are exact and lockfiles are committed.
- `bin/qa_check.sh` checks locked dependencies, Elixir/Rust formatting, warnings, lint, and tests.
- CI runs the same gate from a clean Linux checkout.
- Runtime and capability decisions are documented.
- No database or SQL behavior exists.

## Test Strategy

- deterministic smoke result and each base error field
- repeated NIF load/call behavior
- resource-counter baseline before/after a temporary smoke resource
- QA from repository root with no network service or sibling repository dependency

## Quality Bar

The foundation must fail clearly on incompatible NIF/toolchain combinations, contain panics, avoid normal-scheduler blocking, and expose no native implementation structs in the public API.
