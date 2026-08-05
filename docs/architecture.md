# Architecture

Tursox mirrors the engine's ownership model:

```text
Database -> Connection -> Statement -> Cursor
```

One database resource derives many independent connections. Statements belong
to one connection and bounded cursors belong to one statement. Direct resources
are always available. `Tursox.Pool` and `Tursox.Manager` are optional layers;
Tursox starts neither globally.

Native I/O is driven by one lazily initialized multi-threaded Tokio runtime.
Potentially blocking NIFs use dirty I/O schedulers. Resources have logical close
state and per-resource mutexes; there is no process-global database lock. Every
NIF boundary is panic-contained by Rustler, and deliberately caught panics are
translated to the stable Tursox error shape.

Children retain native parent resources for memory safety. Logical parent close
will invalidate descendant operations rather than freeing memory underneath
them. Counters track logical resources and make lifecycle tests deterministic.

Errors, telemetry, logs, and inspections must not include bound values, result
rows, encryption material, or tokens. SQL is omitted from telemetry by default.
