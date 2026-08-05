# Turso 0.7.2 capability matrix

See the [exact native capability record](compatibility/turso-0.7.2.md) for
lockfile resolutions, source links, feature decisions, target status, and proof.

The native crate pins `turso = 0.7.2` with default features disabled and opts
back into only the deliberate `fts` feature. This avoids Turso's `mimalloc`
global allocator while providing tested Tantivy-backed search. The observations
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
| MVCC passive checkpoint builder switch | Yes, unsafe runtime probe | Rejected |
| Manual local checkpoint Rust method | No | WAL pragma only; MVCC rejected |
| Multiprocess WAL builder switch | Yes, experimental | Validated, not production-supported |
| Cloud sync | Feature-gated | Deferred |
| Interrupt handle | No stable Rust API | Unsupported |
| Read-only/open-mode builder | No stable Rust API | Unsupported |
| FTS index method/functions | Cargo `fts` + builder switch | Supported, opt-in per database |
| Runtime extension loading | Disabled embedded registry | Unsupported |

Builder switches confirmed in 0.7.2 are encryption, attach, custom types,
generated columns, index methods, materialized views, vacuum, multiprocess WAL,
`WITHOUT ROWID`, and MVCC passive checkpointing. Triggers and strict tables are
always enabled despite retained compatibility methods. Exposed experimental
switches remain opt-in; encryption and unsafe passive MVCC checkpointing are rejected.

MVCC is experimental upstream and provides snapshot isolation, not a claim of
serializability. Behavior present only in Turso main is not part of this matrix.
