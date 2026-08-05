# Tursox

Tursox is a low-level Elixir wrapper around the embedded
[Turso](https://github.com/tursodatabase/turso) engine. It preserves Turso's
actual ownership model: one database handle derives many connections, each of
which owns real prepared statements and bounded row cursors.

The planned public layers are:

* direct resources (`Tursox.Database`, `Connection`, `Statement`, `Cursor`),
* an optional shared-handle `DBConnection` pool, and
* an optional caller-supervised manager for many independent databases.

Tursox never starts a global database registry. MVCC support is explicit and is
always documented as experimental upstream.

## Status

Version 0.1.0 is under roadmap-driven development. The native foundation pins
Turso 0.7.2 and disables its default allocator/FTS features. See
[`docs/capabilities.md`](docs/capabilities.md) for the versioned capability
matrix and [`docs/architecture.md`](docs/architecture.md) for runtime rules.

## Installation

Once published, add the exact compatible release to `mix.exs`:

```elixir
def deps do
  [{:tursox, "~> 0.1.0"}]
end
```

Precompiled NIFs are used when checksums are available. Set `TURSOX_BUILD=1` to
force a source build; this requires the Rust toolchain pinned in
`rust-toolchain.toml`.

## Development

Run the authoritative repository gate:

```sh
bin/qa_check.sh
```

No sibling source checkout or network service is required.

## License

MIT. See `LICENSE`.
