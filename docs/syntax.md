# The query language of ROXIE

ROXIE finds log lines with the query language of Wolly.Query (Wolly, after Qualys QQL). The search field of
the pages and `roxie query` take the same queries:

    host:server and level:error and time:last 24h and "mariadb"

The page `/help` (link "Help" beside the search field) explains the same for a visitor; its examples are those
below, which `scripts/check-syntax.sh` holds it to.

A query is never SQL: Wolly.Query reads it, refuses it with the byte that is wrong before anything runs, and binds
every value. Text in quotes reaches the full-text index (SQLite FTS5) as one phrase of letters and digits, so nothing
a visitor writes is FTS5 syntax either.

## Terms

| Term | Finds | Note |
|---|---|---|
| `host:NAME` | the lines of the host NAME | any case; `host:web*` a prefix; `host:"web1.example.org"` as written |
| `source:PATH` | the lines of the file PATH | `source:/var/log/hiawatha/*` a prefix; in quotes as written |
| `level:LEVEL` | the lines of the level | 1 to 16 small letters; ROXIE writes `error`, `warn`, `info`, `debug` |
| `id:N` | the line of number N | |
| `time:DAY` | the lines of the day DAY, `YYYY-MM-DD` in UTC | |
| `time:last N` + `s` `m` `h` `d` `w` | the lines of the window up to now | `time:last 24h` |
| `FIELD:[A .. B]` | a range, both ends taken | for `time` and `id`; a time is seconds since 1970, a day, or `"YYYY-MM-DDTHH:MM:SSZ"` in quotes; a day as the end takes all of it |
| `"WORDS"` | the lines with these words in this order | any case; at most 16 words of at most 64 bytes |

## Operators

`and`, `or`, `not`, in any case, and parentheses. `not` binds closest, then `and`, then `or`:
`a or b and c` is `a or (b and c)`, and `not a and b` is `(not a) and b`. Two terms need an operator between them.

## Ranking

The lines a query finds are ordered by time, the newest first, and of the same second by their number, the newest
first (`ORDER BY at DESC, id DESC` in Wolly.Query). There is no ranking by relevance: a line that holds a word
three times stands where its time puts it.

## Limits

A query is at most 1024 bytes, nests parentheses and `not` at most 16 deep, has at most 64 terms and operators and
at most 8 texts in quotes. A query looks at most at 1000000 lines in its time window (the times its outermost `and`
joins together); with more it is refused with "more lines in the time window than a query looks at", and a
`time:last 24h` or `--since` makes the window smaller.

## Examples

Every example here is a test: `src/Roxie/Find.test.hiq` runs it through `roxie query`'s code against the six lines
below, and the gate (`scripts/check-syntax.sh`) refuses a list here that is not the list of the test. The time of
the test is 2026-10-15T00:00:00Z.

| id | time | host | source | level | line |
|---|---|---|---|---|---|
| 1 | 2026-10-14T23:59:00Z | server | /var/log/syslog | error | mariadb: Table is marked as crashed and should be repaired |
| 2 | 2026-10-14T22:00:00Z | server | /var/log/syslog | info | systemd[1]: Started cron.service |
| 3 | 2026-10-14T23:58:20Z | server | /var/log/hiawatha/access.log | info | GET /index.html 200 |
| 4 | 2026-10-13T01:00:00Z | web1.example.org | /var/log/syslog | warn | disk nearly full on /var |
| 5 | 2026-10-14T23:59:30Z | web1.example.org | /var/log/nginx/error.log | error | upstream timed out while reading |
| 6 | 2026-10-14T23:50:00Z | web2.example.org | /var/log/syslog | debug | cron: job 42 done |

Queries that find lines:

| Query | Lines |
|---|---|
| `host:server` | 3 |
| `host:SERVER` | 3 |
| `host:web*` | 3 |
| `host:"web1.example.org"` | 2 |
| `source:/var/log/hiawatha/*` | 1 |
| `source:"/var/log/syslog"` | 4 |
| `level:error` | 2 |
| `level:debug` | 1 |
| `id:3` | 1 |
| `id:[1 .. 2]` | 2 |
| `"table is marked"` | 1 |
| `"marked table"` | 0 |
| `"TIMED OUT"` | 1 |
| `level:error and host:server` | 1 |
| `level:error or level:warn` | 3 |
| `host:server and not level:info` | 1 |
| `not level:info and host:server` | 1 |
| `host:web1.example.org or host:server and level:error` | 3 |
| `(host:web1.example.org or host:server) and level:error` | 2 |
| `time:last 24h` | 5 |
| `time:last 1h and host:server` | 2 |
| `time:2026-10-13` | 1 |
| `time:[2026-10-13 .. 2026-10-14]` | 6 |
| `time:[1792022000 .. 1792022400]` | 3 |
| `time:["2026-10-14T23:55:00Z" .. "2026-10-15T00:00:00Z"]` | 3 |
| `host:server and level:error and time:last 24h and "mariadb"` | 1 |
| `host:nobody.example.org` | 0 |

Queries that are refused, with the byte where (counted from 0):

| Query | Byte | Why |
|---|---|---|
| `level:ERROR` | 6 | a value the field does not take: a level is small letters |
| `mariadb` | 0 | a word without a field; put text in quotes |
| `"crashed` | 0 | a quote that is not closed |
| `host:server and` | 15 | a term is missing |
| `host:server level:error` | 12 | and, or or a closing parenthesis is missing |
| `time:[2026-10-15 .. 2026-10-01]` | 5 | a range that ends before it starts |
| `colour:red` | 0 | no such field |

## roxie query

    roxie query [--json] [--limit N] [--since SINCE] QUERY...

runs QUERY against the store of the working directory, the collector's (`/var/lib/roxie` on server:
`sudo -u roxie sh -c 'cd /var/lib/roxie && roxie query host:server and level:error'`). The words of QUERY are joined
by spaces, so a query without quotes needs none around it; text in quotes does, for the shell.

- `--limit N`, `-n N`: at most N lines, 1 to 100, 20 without it.
- `--since SINCE`: only lines since SINCE: N and `s`, `m`, `h`, `d` or `w` (the window up to now), a day `YYYY-MM-DD`,
  or seconds since 1970 of 9 to 12 digits. It is joined to the query as `(QUERY) and time:last SINCE` or
  `(QUERY) and time:[SINCE .. NOW]`; any other SINCE is refused, so nothing of a query can come in through it.
- `--json`: the answer as JSON on standard output, of the schema below, a refusal too.
- `-v`: without `--json`, how many lines the query found in all and how many are shown, to standard error.

Without `--json` a line found is one line of output: its time in RFC 3339, host, level, source and text, between
tabs, newest first. Why a query was refused goes to standard error, with the byte:

    roxie: a value the field does not take, at byte 6 of: level:ERROR

### Exit status

| Exit | When |
|---|---|
| 0 | the query ran: it found lines, or none |
| 1 | the command line was wrong (no QUERY, `--limit` out of 1 to 100, an unknown option) |
| 2 | the query or `--since` was refused (`error.kind` `refused` or `since`) |
| 3 | the time window held too many lines (`too-many-lines`) |
| 4 | the store could not be read (`storage`) |

The exit status and `error.kind` of the JSON say the same.

### The JSON, schema 1

A query that ran:

```json
{"schema":1,"version":"0.1.0","query":"host:server","now":1792022400,"total":3,"shown":3,"lines":[
 {"id":1,"at":1792022340,"time":"2026-10-14T23:59:00Z","host":"server","source":"/var/log/syslog","level":"error","line":"mariadb: Table is marked as crashed and should be repaired"}]}
```

| Field | Type | |
|---|---|---|
| `schema` | integer | 1; a change that takes a field away or gives one another meaning makes it 2 |
| `version` | string | the version of roxie, `dev` for a build without a tag |
| `query` | string | the query as it ran, `--since` joined to it |
| `now` | integer | the time the query ran, seconds since 1970 |
| `total` | integer | the lines the query found in all |
| `shown` | integer | the lines in `lines`, at most `--limit` |
| `lines` | array | the lines, newest first |
| `lines[].id` | integer | the number of the line in the store |
| `lines[].at` | integer | its time, seconds since 1970 |
| `lines[].time` | string | its time in RFC 3339, UTC |
| `lines[].host` | string | its host |
| `lines[].source` | string | the file it came from |
| `lines[].level` | string | its level |
| `lines[].line` | string | its text, escaped as JSON escapes a string |

A query that did not run has `error` in place of `total`, `shown` and `lines`:

```json
{"schema":1,"version":"0.1.0","query":"level:ERROR","now":1792022400,"error":{"kind":"refused","problem":"a value the field does not take","position":6}}
```

| `error.kind` | When | `error.position` |
|---|---|---|
| `refused` | the query is refused | the byte of `query`, from 0 |
| `since` | `--since` is refused | `null` |
| `too-many-lines` | more lines in the time window than a query looks at | `null` |
| `storage` | the store could not be read | `null` |

`error.problem` is the reason in a few words, the same as on standard error. The fields come in the order of the
tables; a reader takes them by name.

## Over HTTP: GET /api/query

A programme beside the collector, for example an audit tool, asks the same over HTTPS with a reader's token, made once as the
user roxie in the collector's directory and shown once:

    roxie reader audit            a token for the reader audit (its owner is _reader.audit)
    roxie revoke-reader audit     revokes the tokens of audit

    curl -H "Authorization: Bearer $TOKEN" \
        'https://roxie.example.org/api/query?q=host%3Aocea+and+level%3Aerror&limit=50&since=1h'

`q` is the query (URL-encoded; a plus is a space), `limit` 1 to 100 (20 without it), `since` as `--since`. The answer
is the JSON above, schema 1, `Content-Type: application/json`:

| Status | When |
|---|---|
| 200 | the query ran: it found lines, or none |
| 400 | `q` missing, `limit` not 1 to 100 (text), or the query, `since` or the size of the window refused (JSON with `error`) |
| 401 | no token, or one never given out or revoked |
| 403 | a token that is no reader's, an agent's among them |
| 405 | a verb other than GET |
| 503 | the store could not be read |

A reader's token opens nothing else: no page, and no batch on `/ingest`.
