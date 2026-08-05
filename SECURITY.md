# Security policy

Report suspected vulnerabilities privately to the maintainer listed in
`mix.exs`. Do not include production database contents, bound values, keys, or
tokens in a report unless an encrypted channel has been agreed first.

Tursox 0.2.x exposes experimental and explicitly unsafe engine switches; they
are not production-stable security boundaries. `:runtime_extensions` permits a
native library to execute arbitrary code inside the BEAM and must never load an
untrusted path. Encryption keys are redacted from Tursox observability but still
exist in process memory. Keep untrusted clients behind application-level
authentication, authorization, SQL policy, and resource limits.
