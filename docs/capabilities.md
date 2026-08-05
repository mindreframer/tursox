# Turso 0.7.2 capability matrix

See the [exact native capability record](compatibility/turso-0.7.2.md) for
lockfile resolutions, source links, feature decisions, target status, and proof.

The native crate pins `turso = 0.7.2` with default features disabled and opts
back into deliberate `fts` and `pure-rust-crypto` features. This avoids Turso's
`mimalloc` global allocator while providing search and portable encryption. The observations
below were verified against the published 0.7.2 crate source and Tursox tests.

| Capability | 0.7.2 public API | Tursox 0.1 plan |
|---|---:|---:|
| Local file and `:memory:` builder | Yes | Epic 2 |
| Many `Database::connect` connections | Yes | Epic 2 |
| Busy timeout, autocommit, cache flush | Yes | Epic 2 |
| Real prepared statements and incremental `Rows::next` | Yes | Epic 3 |
| Ordered names and declaration types | Yes | Epic 3 |
| `BusySnapshot` error variant | Yes | Epic 4 |
| `BEGIN CONCURRENT` / MVCC pragma | Engine SQL, experimental | Epic 4 |
| MVCC passive checkpoint builder switch | Yes, unsafe runtime probe | Exposed through `unsafe_features` |
| Manual local checkpoint Rust method | No | WAL/MVCC PRAGMA; PASSIVE MVCC is unsafe child-only |
| Multiprocess WAL builder switch | Yes, experimental | Validated, not production-supported |
| Cloud sync | Feature-gated | Deferred |
| Interrupt handle | No stable Rust API | Unsupported |
| Read-only/open-mode builder | No stable Rust API | Unsupported |
| FTS index method/functions | Cargo `fts` + builder switch | Supported, opt-in per database |
| Encryption | Public Builder + key options | Supported; eight ciphers, explicit opt-in |
| Autovacuum | Core/SDK only; top Builder omission | Exposed by exact-source adapter; pinned behavior partial |
| Runtime extension loading | Per-connection SDK gate | Exposed through `unsafe_features`; Turso ABI required |

All eleven current documented experimental flags are accepted by
`Database.open/2`. Triggers and strict tables are always enabled. Stable-enough
switches use `features`; known process-killing paths use `unsafe_features` but
remain accessible. Runtime extension libraries execute arbitrary native code
inside the BEAM and must export Turso's `register_extension` ABI; SQLean 0.28.3
exports SQLite entry points and is therefore rejected with an exact loader error.

MVCC is experimental upstream and provides snapshot isolation, not a claim of
serializability. Behavior present only in Turso main is not part of this matrix.
