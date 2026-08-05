# Turso 0.7.2 capability matrix

See the [exact native capability record](compatibility/turso-0.7.2.md) for
lockfile resolutions, source links, feature decisions, target status, and proof.

The native crate pins `turso = 0.7.2` with default features disabled. This avoids
installing Turso's `mimalloc` global allocator and avoids accidental FTS support.
The observations below were verified against the published 0.7.2 crate source.

| Capability | 0.7.2 public API | Tursox 0.1 plan |
|---|---:|---:|
| Local file and `:memory:` builder | Yes | Epic 2 |
| Many `Database::connect` connections | Yes | Epic 2 |
| Busy timeout, autocommit, cache flush | Yes | Epic 2 |
| Real prepared statements and incremental `Rows::next` | Yes | Epic 3 |
| Ordered names and declaration types | Yes | Epic 3 |
| `BusySnapshot` error variant | Yes | Epic 4 |
| `BEGIN CONCURRENT` / MVCC pragma | Engine SQL, experimental | Epic 4 |
| MVCC passive checkpoint builder switch | Yes, experimental | Epic 4 |
| Manual local checkpoint Rust method | No | Version-gated pragma only |
| Multiprocess WAL builder switch | Yes, experimental | Validated, not production-supported |
| Cloud sync | Feature-gated | Deferred |
| Interrupt handle | No stable Rust API | Unsupported |
| Read-only/open-mode builder | No stable Rust API | Unsupported |

Builder switches confirmed in 0.7.2 are encryption, attach, custom types,
generated columns, index methods, materialized views, vacuum, multiprocess WAL,
`WITHOUT ROWID`, and MVCC passive checkpointing. Triggers and strict tables are
always enabled despite retained compatibility methods. Every experimental switch
will remain opt-in.

MVCC is experimental upstream and provides snapshot isolation, not a claim of
serializability. Behavior present only in Turso main is not part of this matrix.
