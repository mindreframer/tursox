# Third-party notices

Tursox links open-source Rust and Elixir dependencies. Exact resolved versions
are recorded in `native/tursox_nif/Cargo.lock` and `mix.lock`.

Primary native components include:

- Turso and its Turso SDK/core crates — MIT License,
  <https://github.com/tursodatabase/turso>
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
not enable Turso's optional mimalloc allocator. It deliberately enables only
the Turso `fts` Cargo feature needed by the advertised embedded search support.
