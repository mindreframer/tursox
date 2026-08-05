# Operations, telemetry, and security

Tursox emits Telemetry spans as `[:tursox, operation, :start | :stop |
:exception]` for database open/connect, query execution/start, cursor fetches,
and transactions. Stop measurements include native monotonic `duration`; safe
metadata includes operation kind, configured journal/transaction mode, bounded
fetch size, and result class. Manager lifecycle events use
`[:tursox, :manager, event]`.

SQL, parameters, rows, BLOBs, database contents, keys, tokens, and native
references are never telemetry metadata. Applications should apply their own
policy before attaching tenant identifiers or paths to surrounding spans.

`Tursox.resources/0` returns and emits logical gauges for databases,
connections, statements, cursors, and smoke resources. These counters are
intended for leak diagnostics and deterministic tests, not billing.

## Runtime health

Native calls use Rustler dirty-I/O schedulers and one process-lifetime Tokio
runtime. Cursor fetches are capped at 10,000 rows; pool streams fetch bounded
chunks and retain one checkout only for stream lifetime. A pool worker serializes
one connection, while multiple workers derive independent connections from one
database.

OTP 28 CI sets larger dirty scheduler stacks because Turso 0.7.2 debug MVCC
bootstrap can exceed OTP's default stack. Release builds are still checked under
the same configuration.

## Failure and close behavior

Close is logical, idempotent, and ancestry-aware. Closing a database rejects new
child work and invalidates descendants. A forced manager close is bounded, but
Turso 0.7.2 cannot cancel a native future already executing; that caller must
unwind. Persistent manager entries reopen only after the old pool and database
are closed. In-memory entries are removed after a crash.

Errors are normalized as `%Tursox.Error{code, operation, message, metadata}`.
Retry only documented transient `:busy`, `:locked`, or `:conflict` transaction
errors. Corrupt files, invalid paths/options/parameters, panics, and closed
resources return errors without exposing opaque references or values.

## Release integrity

`bin/package_audit.sh` builds and compiles the unpacked Hex source package.
`.github/workflows/precompiled-release.yml` builds the exact seven-target NIF
2.16 set, directly loads each artifact, and validates archive names/content.
Publishing is an explicit manual workflow input. Checksums must be generated
from published release assets and committed before the no-Rust consumer CI jobs
activate; source builds remain available via `TURSOX_BUILD=1`.

Report vulnerabilities according to [`SECURITY.md`](../SECURITY.md).
