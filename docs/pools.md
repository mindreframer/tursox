# Shared-handle DBConnection pools

`Tursox.Pool` is optional. Starting one opens (or receives) exactly one
`Tursox.Database`; `pool_size` controls connections derived from that handle and
never database opens. In-memory workers therefore share state.

```elixir
{:ok, pool} = Tursox.Pool.start_link(database: :memory, pool_size: 4)
{:ok, _} = Tursox.Pool.execute(pool, "CREATE TABLE items (id INTEGER)")
{:ok, result} = Tursox.Pool.query(pool, "SELECT id FROM items", [], max_rows: 1_000)
```

A database passed as `%Tursox.Database{}` remains caller-owned unless
`own_database: true`. A path or `:memory` is owned and closes after workers drain.
`Tursox.Pool.pool/1` returns the underlying DBConnection pool for advanced use.

Prepared query references map to real native statements per worker. If a query
moves to another pooled worker it is prepared there as well; close frees the
current worker's copy and all remaining copies close on worker/pool shutdown.
Transient convenience calls close their statement immediately.

Materialized pool queries have a bounded `max_rows` option (default 10,000).
`Pool.stream/4` holds one checkout and fetches native chunks controlled by
`chunk_size` (default 500); halt deterministically deallocates its cursor.

DBConnection transaction checkouts provide exclusive connection ownership and
forward `mode: :deferred | :immediate | :exclusive | :concurrent`. Expected
constraint/busy errors do not replace a worker. Fatal I/O, corruption, or closed
resource errors disconnect only that worker. Turso 0.7.2 may report MVCC
write/write conflicts during statement execution, preserving `Tursox.Error`;
DBConnection's commit callback contract cannot return a non-disconnecting custom
commit error, so applications should keep whole-transaction retry outside the
adapter when a conflict survives until commit.
