# Supervised multi-database managers

`Tursox.Manager` is optional and caller-supervised. It has no module-global
registry or singleton; start multiple managers by pid or caller-selected names.
Tenant IDs remain ordinary terms and are never converted to atoms.

```elixir
{:ok, manager} = Tursox.Manager.start_link(name: MyApp.TenantDatabases, max_databases: 100)
{:ok, pool} = Tursox.Manager.open(manager, tenant_id, "data/tenant.db", pool_size: 4)
```

`open/4`, `lookup/2`, `fetch/2`, `list/1`, and `close/3` are serialized by one
manager, making duplicate-ID, canonical-path, and capacity decisions atomic
before native allocation. List entries contain only ID, canonical path or
`:memory`, journal mode, pool size, pool pid, and persistence status. Database
options, SQL, parameters, rows, and secrets are excluded.

Each entry owns one database and shared-handle pool. Closing removes it from
lookup before draining, so no new work is admitted. `force: true` is bounded and
kills the pool when requested; Turso 0.7.2 cannot interrupt an already-running
native future, so an existing caller may still need to unwind after force close.

A crashed persistent entry waits for its old DBConnection pool to terminate,
closes the old database handle, then reopens the same canonical path. Data is
preserved. Memory entries are removed after a crash because their contents
cannot be recovered; callers may explicitly reopen a fresh one. Whole-manager
restart does not auto-open a durable catalog.

Manager lifecycle telemetry uses `[:tursox, :manager, event]` and contains safe
ID/path plus result classes only. Multiple managers may use overlapping tenant
IDs without interference.
