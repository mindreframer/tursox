# Tursox 0.2.1 Feature Exposure Correction

- [x] Audit every Roadmap002 `unsupported`/`unsafe` claim against exact Turso 0.7.2 source.
- [x] Expose omitted public builder switches: encryption and unsafe MVCC passive checkpoint.
- [x] Add explicit `unsafe_features` while preserving `features` compatibility for 0.2.x.
- [x] Fix disposable probes to emit phases and classify exact exits/signals; reject setup failures as evidence.
- [x] Test encryption lifecycle, redaction, wrong keys, and available ciphers.
- [x] Document exact blockers for switches absent from the public 0.7.2 API/build, including tested SQLean ABI incompatibility.
- [ ] Bump to 0.2.1, run QA, rebuild all precompiled NIFs, publish checksums/tag/release, and verify consumers/CI.
