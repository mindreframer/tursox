# Third-party notices

Tursox links open-source Rust and Elixir dependencies. Exact resolved versions
are recorded in `native/tursox_nif/Cargo.lock` and `mix.lock`.

Primary native components include:

- Turso and its Turso SDK/core crates — MIT License. The exact published 0.7.2
  top-level crate is vendored under `native/tursox_nif/vendor/turso` with a
  narrow attributed adapter for the already-present SDK autovacuum and runtime
  extension APIs, <https://github.com/tursodatabase/turso/tree/v0.7.2>
- Rustler — MIT OR Apache-2.0,
  <https://github.com/rusterlium/rustler>
- Tokio — MIT License,
  <https://github.com/tokio-rs/tokio>
- Tantivy and its search components — MIT License,
  <https://github.com/quickwit-oss/tantivy>
- `oneshot` 0.1.13 — MIT OR Apache-2.0, exact upstream source and licenses
  vendored under `native/tursox_nif/vendor/oneshot`,
  <https://github.com/faern/oneshot/tree/v0.1.13>

Primary Elixir components include RustlerPrecompiled (MIT), DBConnection
(Apache-2.0), and Telemetry (Apache-2.0). Their copyright notices and complete
license texts are available in their linked source distributions. Tursox does
not enable Turso's optional mimalloc allocator. It deliberately enables the
Turso `fts` and `pure-rust-crypto` Cargo features needed by advertised search
and portable encryption support.
