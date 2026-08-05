# Transactions and experimental MVCC

Tursox supports deferred, immediate, exclusive, and concurrent modes. Stable
Turso 0.7.2 has no Rust `TransactionBehavior::Concurrent` variant, so concurrent
mode deliberately executes public `BEGIN CONCURRENT` SQL after verifying that
the database was opened with `journal_mode: :mvcc`.

```elixir
{:ok, value} =
  Tursox.Connection.transaction(conn, fn ->
    :ok = Tursox.Connection.execute(conn, "UPDATE counters SET value = value + 1")
    :updated
  end, mode: :concurrent)
```

A callback return of `{:error, reason}` rolls back. Raises, throws, and exits also
roll back before propagating. Nesting is rejected. Direct connections are
sequential resources and callers must not share one connection between callback
owners; DBConnection checkouts provide process isolation in the pooled layer.

`retry_transaction/3` reruns the entire callback, never just `COMMIT`. Attempts
are finite and only `:busy`/`:busy_snapshot` errors retry. Backoff and jitter are
explicit functions or bounded millisecond values.

## MVCC behavior on 0.7.2

MVCC is experimental upstream. Tests prove snapshot isolation, concurrent
disjoint writers, same-row conflict rollback, conflict classification,
durability, and integrity. The engine may detect a write/write conflict during
the write itself rather than waiting for commit; Tursox preserves either
`BusySnapshot` or retryable busy classification and never promises commit-only
conflicts. MVCC is snapshot isolation, not serializability.

`mvcc_checkpoint_threshold` accepts and reads back non-negative integers. Manual
MVCC passive checkpointing is rejected: executable 0.7.2 probing of the passive
builder switch plus `wal_checkpoint(PASSIVE)` caused a native bus error. WAL
checkpoint modes remain available and return the engine's ordered three-integer
row. Tursox exposes no high-level interrupt/query timeout because the pinned
public Rust connection API has none.
