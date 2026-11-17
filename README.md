<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/logo/roxie-wordmark-dark.svg">
  <img src="docs/logo/roxie-wordmark-light.svg" alt="ROXIE" width="310" height="100">
</picture>

ROXIE: Ranked Objects eXtended Index Engine. A log collector written in Hilde on Wolly

Website: https://hilde-lang.org/wolly/

# ROXIE

A log collector for a handful of hosts, written in
[Hilde](https://github.com/heikozim/hilde) on
[Wolly](https://github.com/heikozim/hilde-wolly).

## Features

- **Agent** on each host: reads the new lines of its log files, their time
  and level (syslog in RFC 3339 and BSD form, Hiawatha, a priority, a JSON
  or logfmt field), guesses the level of the rest, and sends numbered
  batches over HTTPS with the client certificate and token of its host
- **Collector** behind Hiawatha as FastCGI: keeps the lines with full-text
  search (FTS5), counts them, and shows them on a dashboard drawn on the
  server; the only script is htmx, served by ROXIE itself
- **Query language** with a JSON output and a reader API, see
  [docs/syntax.md](docs/syntax.md):

  ```
  host:server and level:error and time:last 24h and "mariadb"
  ```
- **Sign-in** through an OpenID Connect provider such as
  [RAMBO](https://github.com/heikozim/hilde-rambo)
- **Sandbox:** pledge and unveil on OpenBSD, Landlock and seccomp on Linux

## Quick start

Inside the build container of Wolly, with a Wolly tree beside this one:

```
make build WOLLY_ROOT=../hilde-wolly
make test  WOLLY_ROOT=../hilde-wolly
```

## Commands

| Command | Purpose |
|---|---|
| `roxie` | the collector, a FastCGI responder on `/run/roxie/roxie.sock` (`--socket` or `ROXIE_SOCKET` for another) |
| `roxie serve SOCKET` | the same on the socket SOCKET (an absolute path) |
| `roxie allow NAME SUB` | the account SUB of the provider signs in as the user NAME |
| `roxie revoke-user NAME` | no account signs in as NAME any more |
| `roxie token HOST` | a token for the agent of HOST, shown once |
| `roxie revoke HOST` | revoke the tokens of HOST |
| `roxie reader NAME` | a token for the reader NAME (`GET /api/query`), shown once |
| `roxie revoke-reader NAME` | revoke the tokens of the reader NAME |
| `roxie agent CONFIG` | the agent, a round every few seconds until SIGTERM |
| `roxie agent-once CONFIG` | one round of the agent |
| `roxie prune DAYS` | take lines and samples older than DAYS days out of the store |
| `roxie relevel` | give every kept line the level of today's rules |
| `roxie query QUERY...` | the lines QUERY finds, newest first; `--json`, `--limit N`, `--since SINCE` |
| `roxie doctor` | check the files of the collector in the working directory and its socket |
| `roxie info` | the banner, the name, the version, the build, the system |
| `roxie version [--full]` | the version from the tag of the build; `-V`, `--version` |
| `roxie -s` | what confines the process |
| `roxie setup completion bash\|zsh\|fish` | the completion of a shell |
| `roxie setup manual` | the manual page in mdoc |

## Running

The collector works in its working directory: `roxie.db`, `csrf.key`,
`pseudonym.key`, `audit.log`, `access.log`, `known-passwords.txt` from
`share/`, and `rambo.conf` and `rambo-secret` for the sign-in.  Hiawatha in
front of it needs `HTTPAuthToCGI = yes` (the token of `/ingest`) and a
`MaxRequestSize` of at least 1100 (KB), as in `scripts/in-e2e.sh`.

## Testing

- `make test`: unit tests, contract tests, the contract lint, the build and
  the end-to-end test behind Hiawatha (`scripts/in-gate.sh`)

## License

Copyright (c) 2026 Heiko Zimmermann <code@heiko-zimmermann.com>

ROXIE is licensed under the Apache License 2.0 with LLVM Exceptions; see
[LICENSE](LICENSE).  `share/htmx.min.js` is htmx, Zero-Clause BSD; see
[NOTICE](NOTICE).
