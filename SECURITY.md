# Security policy

Report suspected vulnerabilities privately to the maintainer listed in
`mix.exs`. Do not include production database contents, bound values, keys, or
tokens in a report unless an encrypted channel has been agreed first.

Tursox 0.1.x is an initial embedded binding. Turso MVCC and builder switches
marked experimental upstream are not represented as production-stable security
boundaries. Keep untrusted clients behind application-level authentication,
authorization, SQL policy, and resource limits.
