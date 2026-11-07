#!/usr/bin/env bash
# Runs inside the build container, from the root of a ROXIE tree beside a Wolly tree
# at $WOLLY_ROOT, after scripts/in-build.sh: the collector behind a
# Hiawatha of its own with TLS, a certificate made for the run, and an
# agent that sends to it over HTTPS -- the whole way of a line, from a log
# file through the outbox and /ingest to the search page.  Every case asks
# with curl on 127.0.0.1:$PORT or runs roxie itself.  The last case is the
# control: with roxie stopped Hiawatha must answer 503, so the answers
# before it were roxie's.  Ends with one line of counts.
#
#     WOLLY_ROOT=/path/wolly bash scripts/in-e2e.sh
[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "ABORT: bash ${BASH_VERSION} too old" >&2; exit 9; }
set -u
[ -r /etc/wolly-dev ] || { echo "ABORT: not inside the build container -- nothing ran" >&2; exit 9; }
[ -x _run/bin/roxie ] || { echo "ABORT: _run/bin/roxie missing -- scripts/in-build.sh builds it" >&2; exit 9; }
command -v openssl > /dev/null 2>&1 || { echo "ABORT: openssl not on PATH -- nothing ran" >&2; exit 9; }
HIAWATHA=/usr/local/sbin/hiawatha
[ -x "$HIAWATHA" ] || { echo "ABORT: no Hiawatha at $HIAWATHA -- nothing ran" >&2; exit 9; }
PORT=${PORT:-18521}
BASE="https://127.0.0.1:$PORT"
# The agents' port: Hiawatha asks every client for a certificate of the
# agents' CA there (RequiredCA).
PORT2=${PORT2:-18522}
MTLS="https://127.0.0.1:$PORT2"
ORIGIN=$BASE
# The stand-in of RAMBO: its issuer, the account it signs in,
# the client and its secret.
PORT3=${PORT3:-18533}
ISSUER="https://127.0.0.1:$PORT3"
ANN_SUB="01JROXIEANN0000000000000E2E"
for u in "$BASE" "$MTLS"; do
	if curl -s -k -o /dev/null --max-time 1 "$u/"; then
		echo "ABORT: something answers at $u -- nothing ran" >&2
		exit 9
	fi
done
D=$PWD/_run/e2e
rm -rf "$D" && mkdir -p "$D/config" "$D/www" "$D/log" "$D/work" "$D/out" "$D/run" || exit 9
cp /opt/hiawatha/mimetype.conf "$D/config/mimetype.conf" || exit 9
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
	-subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1 \
	-keyout "$D/config/key.pem" -out "$D/config/cert.pem" > "$D/openssl.out" 2>&1 || { cat "$D/openssl.out"; exit 9; }
cat "$D/config/key.pem" "$D/config/cert.pem" > "$D/config/tls.pem" && chmod 600 "$D/config/tls.pem" || exit 9
# A second certificate, for an agent that trusts the wrong one.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
	-subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1 \
	-keyout "$D/config/other-key.pem" -out "$D/config/other.pem" > "$D/openssl2.out" 2>&1 || { cat "$D/openssl2.out"; exit 9; }
# The agents' CA and three agents: web1 and web2 of the CA, and a stranger
# whose certificate signs itself.
agent_cert() {
	local name=$1
	openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj "/O=ROXIE/CN=$name" \
		-keyout "$D/config/$name.key" -out "$D/config/$name.csr" > "$D/openssl-$name.out" 2>&1 || return 1
	openssl x509 -req -sha256 -in "$D/config/$name.csr" -CA "$D/config/agents-ca.pem" -CAkey "$D/config/agents-ca.key" \
		-set_serial "0x$(openssl rand -hex 8)" -days 1 -out "$D/config/$name.pem" >> "$D/openssl-$name.out" 2>&1
}
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj "/O=ROXIE/CN=agents of the run" \
	-keyout "$D/config/agents-ca.key" -out "$D/config/agents-ca.pem" > "$D/openssl-ca.out" 2>&1 || { cat "$D/openssl-ca.out"; exit 9; }
agent_cert web1.example.org || { cat "$D/openssl-web1.example.org.out"; exit 9; }
agent_cert web2.example.org || { cat "$D/openssl-web2.example.org.out"; exit 9; }
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj "/O=ROXIE/CN=web1.example.org" \
	-keyout "$D/config/stranger.key" -out "$D/config/stranger.pem" > "$D/openssl-stranger.out" 2>&1 || { cat "$D/openssl-stranger.out"; exit 9; }
WEB1=(--cert "$D/config/web1.example.org.pem" --key "$D/config/web1.example.org.key")
WEB2=(--cert "$D/config/web2.example.org.pem" --key "$D/config/web2.example.org.key")
cp _run/bin/roxie share/known-passwords.txt "$D/" || exit 9
# The icons in the WebsiteRoot, as install-server.sh puts them.
mkdir -p "$D/www/icons" && cp share/icons/favicon.ico share/icons/apple-touch-icon.png "$D/www/" && cp share/icons/roxie-*.png "$D/www/icons/" || exit 9
# The stylesheet, as install-server.sh puts it.
cp share/roxie.css "$D/www/style.css" || exit 9

printf '%s\n' \
	"ServerString = none" \
	"PidFile = $D/hiawatha.pid" \
	"WorkDirectory = $D/work" \
	"SystemLogfile = $D/log/system.log" \
	"GarbageLogfile = $D/log/garbage.log" \
	"ExploitLogfile = $D/log/exploit.log" \
	"Binding {" "    Port = $PORT" "    Interface = 127.0.0.1" "    MaxRequestSize = 1100" "    TLScertFile = $D/config/tls.pem" "}" \
	"Binding {" "    Port = $PORT2" "    Interface = 127.0.0.1" "    MaxRequestSize = 1100" "    TLScertFile = $D/config/tls.pem" "    RequiredCA = $D/config/agents-ca.pem" "}" \
	"FastCGIserver {" "    FastCGIid = ROXIE" "    ConnectTo = $D/run/roxie.sock" "    SessionTimeout = 10" "}" \
	"UrlToolkit {" "    ToolkitID = all" "    $(sed -n 's/^    \(Match \^.* Return\)$/\1/p' deploy/hiawatha-roxie.urltoolkit)" "    Match .* UseFastCGI ROXIE" "}" \
	"Hostname = 127.0.0.1" \
	"HTTPAuthToCGI = yes" \
	"TimeForCGI = 10" \
	"WebsiteRoot = $D/www" \
	"AccessLogfile = $D/log/access.log" \
	"ErrorLogfile = $D/log/error.log" \
	"UseToolkit = all" > "$D/config/hiawatha.conf"

cases=0
good=0
# expect <name> <status> <path> <pattern-in-headers-and-body> [curl args...]
expect() {
	local name=$1 status=$2 path=$3 pattern=$4
	shift 4
	cases=$((cases + 1))
	last="$D/out/$cases"
	local got
	got=$(curl -s --cacert "$D/config/cert.pem" -D "$last.head" -o "$last.body" -w '%{http_code}' --max-time 20 "$@" "${AT:-$BASE}$path")
	if [ "$got" = "$status" ] && cat "$last.head" "$last.body" | tr -d '\r' | grep -qE -- "$pattern"; then
		good=$((good + 1))
		echo "ok    $name ($got)"
	else
		echo "FAIL  $name: status $got, want $status, pattern '$pattern'"
		tr -d '\r' < "$last.head" | sed 's/^/      /'
		dd if="$last.body" bs=600 count=1 2> /dev/null | sed 's/^/      /'
		grep -E 'roxie-(count|problem)|<tr class=' "$last.body" | sed 's/^/    > /'
		echo
	fi
}
check() {
	local name=$1
	shift
	cases=$((cases + 1))
	if "$@"; then
		good=$((good + 1))
		echo "ok    $name"
	else
		echo "FAIL  $name"
	fi
}
location_of() { tr -d '\r' < "$last.head" | sed -n 's/^Location: //p' | head -1; }
cookie_of() { tr -d '\r' < "$last.head" | sed -n 's/^Set-Cookie: __Host-wolly=\([0-9a-f]\{64\}\);.*/\1/p' | head -1; }
csrf_of() { sed -n 's/.*name="csrf" value="\([0-9a-f]\{64\}\)".*/\1/p' "$last.body" | head -1; }
SAME=(-H "Sec-Fetch-Site: same-origin" -H "Origin: $ORIGIN")
# The TOTP code of the base32 secret $1 at the step of now plus $2 steps:
# RFC 6238 with HMAC-SHA256, 6 digits, 30 seconds, as Wolly.Totp makes it
# (after Wolly's scripts/e2e-login.sh).
totp_code() {
	python3 -I -c 'import base64, hashlib, hmac, struct, sys, time
key = base64.b32decode(sys.argv[1] + "=" * (-len(sys.argv[1]) % 8))
mac = hmac.new(key, struct.pack(">Q", int(time.time()) // 30 + int(sys.argv[2])), hashlib.sha256).digest()
at = mac[-1] & 15
print("%06d" % ((struct.unpack(">I", mac[at:at + 4])[0] & 0x7fffffff) % 1000000))' "$1" "$2"
}

echo "== prepared"
printf '%s\n' "issuer $ISSUER" "client roxie" "redirect $BASE/oauth/callback" "ca $D/config/cert.pem" > "$D/rambo.conf" || exit 9
(umask 077 && printf '%s\n' "secret-of-the-end-to-end" > "$D/rambo-secret") || exit 9
(cd "$D" && ./roxie allow ann "$ANN_SUB" > allow.out 2>&1)
check "the account of ann at RAMBO allowed" grep -qx "roxie: the account is allowed" "$D/allow.out"
(cd "$D" && ./roxie allow ann "a b" > allow-bad.out 2>&1)
check "an account with a space is refused" grep -q "refused" "$D/allow-bad.out"
(cd "$D" && ./roxie allow Ann "$ANN_SUB" > allow-name.out 2>&1)
check "no user name is refused" grep -q "refused" "$D/allow-name.out"
# Every process the run starts goes into pids and ends with it: the stand-in
# of RAMBO was started before the list was made, outlived the run and kept
# its port, and a second run in the same machine talked to the first one's.
pids=()
stop_all() {
	local p
	for p in "${pids[@]}"; do kill -TERM "$p" 2> /dev/null; done
}
trap stop_all EXIT
check "the port of RAMBO's stand-in is free" bash -c "! ss -Hltn 'sport = :$PORT3' | grep -q ."
# Each wait for a process to come up asks every 0.1 s for at most 60 s and
# stops as soon as it is there.  It was 50 tries: a refused connection ends
# curl at once, so they were 5 s, and beside a full server Hiawatha was not
# up in them.
python3 -I scripts/rambo-standin.py "$PORT3" "$ANN_SUB" roxie secret-of-the-end-to-end "$D/config/cert.pem" "$D/config/key.pem" "$D" > "$D/rambo.out" 2>&1 &
pids+=("$!")
for ((i = 1; i <= 600; i++)); do grep -q "ready" "$D/rambo.out" 2> /dev/null && break; sleep 0.1; done
check "the stand-in of RAMBO is up" grep -q "ready" "$D/rambo.out"
(cd "$D" && ./roxie token web1.example.org > token 2> token.err && chmod 600 token)
check "a token for web1.example.org: 64 hex digits" grep -qxE '[0-9a-f]{64}' "$D/token"
(cd "$D" && ./roxie token "not a host" > bad-token.out 2>&1)
check "a token for no host name is refused" grep -q "refused" "$D/bad-token.out"
# agent_conf <file> <ca> <name of the certificate> <state>
agent_conf() {
	printf '%s\n' "collector $MTLS/ingest" "ca $2" "certificate $D/config/$3.pem" "key $D/config/$3.key" "token $D/token" \
		"state $D/$4" "every 1" "file $D/app.log" > "$D/$1"
}
agent_conf agent.conf "$D/config/cert.pem" web1.example.org agent.db
agent_conf agent-other.conf "$D/config/other.pem" web1.example.org agent-other.db
agent_conf agent-web2.conf "$D/config/cert.pem" web2.example.org agent-web2.db
agent_conf agent-stranger.conf "$D/config/cert.pem" stranger agent-stranger.db
# A line of the BSD form of today, by the clock and the zone of the test,
# which the agent reads too.
printf '%s\n' "$(LC_ALL=C date '+%b %e %H:%M:%S') server systemd[1]: Started." "mysqld: Table is marked as crashed and failed" "a line with <script>alert(1)</script> in it" > "$D/app.log"

(cd "$D" && ./roxie serve relative/roxie.sock > serve-relative.out 2>&1)
check "a relative socket path is refused" grep -q "refused: SOCKET" "$D/serve-relative.out"
(cd "$D" && ./roxie serve "/$(printf 'x%.0s' {1..100})" > serve-long.out 2>&1)
check "a socket path of 101 bytes is refused" grep -q "refused: SOCKET" "$D/serve-long.out"
(cd "$D" && exec setsid stdbuf -oL ./roxie serve "$D/run/roxie.sock" > "$D/roxie.out" 2>&1 < /dev/null) &
app=$!
pids+=("$app")
for ((i = 1; i <= 600; i++)); do
	[ -S "$D/run/roxie.sock" ] && break
	kill -0 "$app" 2> /dev/null || break
	sleep 0.1
done
echo "roxie-socket=$([ -S "$D/run/roxie.sock" ] && echo yes || echo no)"
check "the socket is made with mode 660" [ "$(stat -c %a "$D/run/roxie.sock")" = 660 ]
setsid "$HIAWATHA" -d -c "$D/config" > "$D/hiawatha.out" 2>&1 < /dev/null &
web=$!
pids+=("$web")
for ((i = 1; i <= 600; i++)); do
	curl -s --cacert "$D/config/cert.pem" -o /dev/null --max-time 1 "$BASE/style.css" && break
	kill -0 "$web" 2> /dev/null || break
	sleep 0.1
done
echo "hiawatha-alive=$(kill -0 "$web" 2> /dev/null && echo yes || echo no)"

echo "== without a session or a token"
expect "the dashboard sends a visitor to log in" 303 "/" '^Location: /login'
expect "the style sheet is public" 200 "/style.css" 'wolly-panel'
check "it is share/roxie.css, served by Hiawatha" cmp -s "$last.body" share/roxie.css
check "with these colours" grep -q -- '--bg: #24300f;' "$last.body"
check "and the logo before the name" grep -qF 'url("/icons/roxie-48.png")' "$last.body"
check "the toolkit of the test has the rule of the files" grep -qF 'Match ^/(style\.css|favicon' "$D/config/hiawatha.conf"
expect "the favicon is a file of the site" 200 "/favicon.ico" '^Content-Type: image/'
check "byte for byte the one of share/icons" cmp -s "$last.body" share/icons/favicon.ico
expect "an icon of the list, the logo" 200 "/icons/roxie-48.png" '^Content-Type: image/png'
expect "the apple-touch-icon" 200 "/apple-touch-icon.png" '^Content-Type: image/png'
expect "a name off the list goes to ROXIE, not to the directory" 404 "/icons/" '^X-Request-Id: [0-9a-f]{32}'
expect "the login sends the visitor to RAMBO with PKCE" 303 "/login" "^Location: https://127\\.0\\.0\\.1:$PORT3/authorize\\?.*code_challenge_method=S256"
expect "a search without a session" 303 "/search?q=level:error" '^Location: /login'
expect "the help without a session" 303 "/help" '^Location: /login'
expect "a batch on the port of the pages, without a certificate" 403 "/ingest" '^a client certificate is needed' --data-binary $'roxie 1 1\n1\tinfo\t/a\tx\n'
expect "the same with the host's token" 403 "/ingest" '^a client certificate is needed' -H "Authorization: Bearer $(cat "$D/token")" --data-binary $'roxie 1 1\n1\tinfo\t/a\tx\n'
expect "a GET of /ingest" 405 "/ingest" '^Allow: POST'
echo "== the agents' port: mutual TLS"
c0=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$D/config/cert.pem" --max-time 10 --data-binary x "$MTLS/ingest"); r0=$?
check "without a certificate no handshake" bash -c "[ '$c0' = 000 ] && [ $r0 -ne 0 ]"
c1=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$D/config/cert.pem" --cert "$D/config/stranger.pem" --key "$D/config/stranger.key" --max-time 10 --data-binary x "$MTLS/ingest"); r1=$?
check "a certificate of no CA it knows: no handshake" bash -c "[ '$c1' = 000 ] && [ $r1 -ne 0 ]"
AT=$MTLS expect "a certificate of the CA, no token" 401 "/ingest" '.' "${WEB1[@]}" --data-binary $'roxie 1 1\n1\tinfo\t/a\tx\n'
AT=$MTLS expect "a token never given out" 401 "/ingest" '.' "${WEB1[@]}" -H "Authorization: Bearer $(printf '%064d' 0)" --data-binary $'roxie 1 1\n1\tinfo\t/a\tx\n'
AT=$MTLS expect "web2's certificate with web1's token" 403 "/ingest" "^the token is not of the certificate's host" "${WEB2[@]}" -H "Authorization: Bearer $(cat "$D/token")" --data-binary $'roxie 1 1\n1\tinfo\t/a\tx\n'
expect "a header that claims a certificate is no certificate" 403 "/ingest" '^a client certificate is needed' -H "TLS-Subject-DN: CN=web1.example.org" -H "Authorization: Bearer $(cat "$D/token")" --data-binary $'roxie 1 1\n1\tinfo\t/a\tx\n'

echo "== the agent"
(cd "$D" && ./roxie agent-once agent.conf > agent1.out 2>&1)
a1=$?
check "a round of the agent ends with 0" [ "$a1" -eq 0 ]
check "three lines, one batch taken" grep -q "lines 3, batches taken 1" "$D/agent1.out"
(cd "$D" && ./roxie agent-once agent.conf > agent2.out 2>&1)
check "a round with nothing new says nothing" [ ! -s "$D/agent2.out" ]
printf '%s\n' "disk almost full" "warning: queue long" >> "$D/app.log"
(cd "$D" && ./roxie agent-once agent.conf > agent3.out 2>&1)
check "two more lines, one batch" grep -q "lines 2, batches taken 1" "$D/agent3.out"
(cd "$D" && ./roxie agent-once agent-other.conf > agent4.out 2>&1)
a4=$?
check "an agent that trusts another certificate keeps its batch back" bash -c "[ $a4 -ne 0 ] && grep -q 'kept back at status 0' '$D/agent4.out'"
(cd "$D" && ./roxie agent-once agent-web2.conf > agent5.out 2>&1)
a5=$?
check "web2's agent with web1's token keeps its batch back at 403" bash -c "[ $a5 -ne 0 ] && grep -q 'kept back at status 403' '$D/agent5.out'"
(cd "$D" && ./roxie agent-once agent-stranger.conf > agent6.out 2>&1)
a6=$?
check "an agent of no CA the collector knows keeps its batch back" bash -c "[ $a6 -ne 0 ] && grep -q 'kept back at status 0' '$D/agent6.out'"
token=$(cat "$D/token")
AT=$MTLS expect "a batch sent again is repeated" 200 "/ingest" '^repeated' "${WEB1[@]}" -H "Authorization: Bearer $token" --data-binary $'roxie 1 1\n1792022400\tinfo\t/a\tx\n'
AT=$MTLS expect "a refused batch names line and problem" 400 "/ingest" '^line 1: BadLevel' "${WEB1[@]}" -H "Authorization: Bearer $token" --data-binary $'roxie 1 99\n1\tERROR\t/a\tx\n'

echo "== a reader's queries"
(cd "$D" && ./roxie reader audit > reader 2> reader.err && chmod 600 reader)
check "a token for the reader audit: 64 hex digits" grep -qxE '[0-9a-f]{64}' "$D/reader"
(cd "$D" && ./roxie reader Lu_cio > bad-reader.out 2>&1)
check "a reader that is no name is refused" grep -q "refused" "$D/bad-reader.out"
(cd "$D" && ./roxie token _reader.audit > reader-as-host.out 2>&1)
check "roxie token gives out no reader's token" bash -c "grep -q 'refused' '$D/reader-as-host.out' && ! grep -qxE '[0-9a-f]{64}' '$D/reader-as-host.out'"
reader=$(cat "$D/reader")
expect "a query without a token" 401 "/api/query?q=host:web1.example.org" '^WWW-Authenticate: Bearer'
expect "the agent's token opens no query" 403 "/api/query?q=host:web1.example.org" "no reader's" -H "Authorization: Bearer $token"
expect "the reader's query: JSON of schema 1" 200 "/api/query?q=host%3Aweb1.example.org&limit=100" '"schema":1' -H "Authorization: Bearer $reader"
check "with the lines of the agent in it" grep -q 'disk almost full' "$last.body"
check "as JSON" bash -c "tr -d '\r' < '$last.head' | grep -q '^Content-Type: application/json'"
expect "a plus is a space, the level as the CLI takes it" 200 "/api/query?q=host%3Aweb1.example.org+and+level%3Awarn&limit=100" '"schema":1' -H "Authorization: Bearer $reader"
check "only the warning" bash -c "grep -q 'queue long' '$last.body' && ! grep -q 'disk almost full' '$last.body'"
expect "a refused query, as JSON" 400 "/api/query?q=level%3AERROR" '"kind":"refused"' -H "Authorization: Bearer $reader"
expect "a limit off 1 to 100" 400 "/api/query?q=host%3Aweb1.example.org&limit=500" 'limit is 1 to 100' -H "Authorization: Bearer $reader"
AT=$MTLS expect "the reader's token sends no batch" 403 "/ingest" "^the token is not of the certificate's host" "${WEB1[@]}" -H "Authorization: Bearer $reader" --data-binary $'roxie 1 1\n1\tinfo\t/a\tfrom a reader\n'
(cd "$D" && ./roxie revoke-reader audit > revoke-reader.out 2>&1)
check "revoke-reader revokes the reader's tokens" grep -q "tokens revoked" "$D/revoke-reader.out"
expect "a revoked reader opens nothing" 401 "/api/query?q=host:web1.example.org" '^WWW-Authenticate: Bearer' -H "Authorization: Bearer $reader"

echo "== refused by RAMBO"
# rambo-secret is read with each sign-in: a wrong one, and RAMBO refuses the
# code; the journal (standard output of serve) says how, without the secret.
(umask 077 && printf '%s\n' "a-wrong-secret-of-the-test" > "$D/rambo-secret") || exit 9
expect "a sign-in begun with a wrong secret" 303 "/oauth/start" "^Location: https://127\\.0\\.0\\.1:$PORT3/authorize\\?"
sx=$(cookie_of)
bx=$(curl -s --cacert "$D/config/cert.pem" -o /dev/null -w '%{redirect_url}' --max-time 10 "$(location_of)")
expect "RAMBO refuses the code: 502" 502 "${bx#"$BASE"}" 'the journal of roxie says why' -b "__Host-wolly=$sx"
check "the journal names kind, status and error" grep -q "roxie: RAMBO did not give the tokens: refused, status 401, error invalid_client" "$D/roxie.out"
check "and not the secret" bash -c "! grep -q 'a-wrong-secret-of-the-test' '$D/roxie.out'"
(umask 077 && printf '%s\n' "secret-of-the-end-to-end" > "$D/rambo-secret") || exit 9

echo "== logged in"
expect "/oauth/start, where the tile of RAMBO points, begins a sign-in" 303 "/oauth/start?iss=$ISSUER" "^Location: https://127\\.0\\.0\\.1:$PORT3/authorize\\?"
s1=$(cookie_of)
auth=$(location_of)
check "with state, nonce and the client" bash -c "[[ '$auth' == *client_id=roxie* && '$auth' == *state=* && '$auth' == *nonce=* ]]"
back=$(curl -s --cacert "$D/config/cert.pem" -o /dev/null -w '%{redirect_url}' --max-time 10 "$auth")
check "RAMBO sends the browser back to the callback" bash -c "[[ '$back' == '$BASE/oauth/callback?'* ]]"
callback=${back#"$BASE"}
expect "signed in: the callback opens a session" 303 "$callback" '^Location: /$' -b "__Host-wolly=$s1"
s2=$(cookie_of)
check "a new session after the sign-in" bash -c "[ -n '$s2' ] && [ '$s2' != '$s1' ]"
expect "a code taken once" 400 "$callback" 'unknown here' -b "__Host-wolly=$s1"
expect "the dashboard" 200 "/" 'id="panel-lines"' -b "__Host-wolly=$s2"
check "it loads htmx from ROXIE itself" grep -q '<script src="/htmx.min.js"></script>' "$last.body"
check "htmx adds no style and evaluates nothing" grep -qF "<meta name=\"htmx-config\" content='{\"includeIndicatorStyles\":false,\"allowEval\":false,\"allowScriptTags\":false}'>" "$last.body"
check "each panel asks for itself every minute" grep -q 'id="panel-lines" hx-get="/panel/lines" hx-trigger="every 60s" hx-swap="outerHTML"' "$last.body"
check "without script it refreshes itself every minute" grep -q '<noscript><meta http-equiv="refresh" content="60"></noscript>' "$last.body"
check "it has the search field" grep -q 'action="/search"' "$last.body"
check "the foot of the page: the version the build was given, the words, the holder" grep -qF '<footer class="site-foot">ROXIE v9.8.7 - Ranked Objects eXtended Index Engine - (c) 2026 <a href="https://www.heiko-zimmermann.com/" target="_blank" rel="noopener noreferrer">Heiko Zimmermann</a></footer>' "$last.body"
check "one foot, right before the end of the body" bash -c "[ \$(grep -c 'class=\"site-foot\"' '$last.body') -eq 1 ] && perl -0777 -ne 'exit(m{</footer>\n</body>} ? 0 : 1)' '$last.body'"
check "the panels of the hosts ask for themselves every minute" grep -q 'id="panel-hosts" hx-get="/panel/hosts" hx-trigger="every 60s" hx-swap="outerHTML"' "$last.body"
check "a section for web1.example.org" grep -q '<h2>web1.example.org</h2>' "$last.body"
expect "the panels of the hosts alone, as htmx asks for them" 200 "/panel/hosts" '<h2>web1.example.org</h2>' -b "__Host-wolly=$s2"
check "their counts link to the search" grep -q 'href="/search?q=host%3a%22web1.example.org%22%20and%20time%3alast%2024h">' "$last.body"
expect "the dashboard again, for its form token" 200 "/" 'id="panel-hosts"' -b "__Host-wolly=$s2"
check "no script of its own in the page" bash -c "[ \$(grep -ci '<script' '$last.body') -eq 1 ] && ! grep -qi '<script>' '$last.body'"
c2=$(csrf_of)
expect "a search: the error line of the host" 200 "/search?q=host:web1.example.org+and+level:error" 'Table is marked as crashed and failed' -b "__Host-wolly=$s2"
check "the page of the search has the same foot" grep -qF '<footer class="site-foot">ROXIE v9.8.7 - Ranked Objects eXtended Index Engine - (c) 2026 <a href="https://www.heiko-zimmermann.com/" target="_blank" rel="noopener noreferrer">Heiko Zimmermann</a></footer>' "$last.body"
expect "the help: the whole query language" 200 "/help" '<h2>The query language</h2>' -b "__Host-wolly=$s2"
check "the help has the search field and the way out" bash -c "grep -q 'action=\"/search\"' '$last.body' && grep -q 'action=\"/logout\"' '$last.body'"
check "its examples are links to their searches" grep -qF '<a href="/search?q=level%3Aerror%20or%20level%3Awarn"><code>level:error or level:warn</code></a>' "$last.body"
check "the page of help has the same foot" grep -qF '<footer class="site-foot">ROXIE v9.8.7 - Ranked Objects eXtended Index Engine - (c) 2026 <a href="https://www.heiko-zimmermann.com/" target="_blank" rel="noopener noreferrer">Heiko Zimmermann</a></footer>' "$last.body"
expect "every head links to the help" 200 "/search?q=level:error" '<a class="roxie-help-link" href="/help">Help</a>' -b "__Host-wolly=$s2"
expect "the panels alone have no foot" 200 "/panel/hosts" '<h2>web1.example.org</h2>' -b "__Host-wolly=$s2"
check "a panel is no page: no foot in it" bash -c "! grep -q 'site-foot' '$last.body'"
expect "two error lines: alert counts as error" 200 "/search?q=host:web1.example.org+and+level:error" '2 lines, 1 to 2 shown' -b "__Host-wolly=$s2"
expect "a line with a script, escaped" 200 "/search?q=%22script+alert%22" '&lt;script&gt;alert\(1\)&lt;/script&gt;' -b "__Host-wolly=$s2"
check "and never as a script" bash -c "! grep -q '<script>alert' '$last.body'"
expect "every line of the host, newest first" 200 "/search?q=host:web1.example.org" '5 lines' -b "__Host-wolly=$s2"
echo "== time and level from the line"
# A line of the BSD form three days ago at noon, without a year or a zone
#: the agent reads it in the zone of the test, in this year.
bsd_day=$(date -d '3 days ago' +%F) || exit 9
printf '%s\n' "203.0.113.62|Thu 01 Oct 2026 21:46:49 +0200|503|10|GET /quiet HTTP/2.0|-" "2026-10-01T21:46:50+02:00 server systemd[1]: Started quiet." "$(LC_ALL=C date -d "$bsd_day 12:00:00" '+%b %e %H:%M:%S') edge sshd[1]: error: the BSD form" >> "$D/app.log"
(cd "$D" && ./roxie agent-once agent.conf > agent7.out 2>&1)
check "three lines that say their time, one batch" grep -q "lines 3, batches taken 1" "$D/agent7.out"
expect "the line of the BSD form is found on its day" 200 "/search?q=host:web1.example.org+and+time:$bsd_day+and+%22the+BSD+form%22" '"roxie-count">1 lines, 1 to 1 shown' -b "__Host-wolly=$s2"
expect "and as error by its message" 200 "/search?q=host:web1.example.org+and+level:error+and+%22the+BSD+form%22" '"roxie-count">1 lines, 1 to 1 shown' -b "__Host-wolly=$s2"
expect "not today" 200 "/search?q=host:web1.example.org+and+time:last+24h+and+%22the+BSD+form%22" '"roxie-count">0 lines<' -b "__Host-wolly=$s2"
expect "both are found on the day they say, not today" 200 "/search?q=host:web1.example.org+and+time:2026-10-01" '"roxie-count">2 lines, 1 to 2 shown' -b "__Host-wolly=$s2"
expect "none of the lines of today is on that day" 200 "/search?q=host:web1.example.org+and+time:2026-10-01+and+%22crashed%22" '"roxie-count">0 lines<' -b "__Host-wolly=$s2"
expect "the 503 of Hiawatha is error by its status, without a word of error" 200 "/search?q=host:web1.example.org+and+level:error+and+%22quiet%22" 'GET /quiet' -b "__Host-wolly=$s2"
check "and the line of syslog that says quiet is not" bash -c "! grep -q 'Started quiet' '$last.body'"
echo "== relevel"
# A line of slog that an older agent sent as error, in a batch numbered as
# a state made now would number it: above the agent-once runs of
# the host before, below the agents that keep running, started later.
printf 'roxie 1 %s\n%s\terror\t/var/log/syslog\tlucio-api[1]: {"level":"INFO","msg":"relevelme","error_class":""}\n' "$(( $(date +%s) * 1000 + 1 ))" "$(date +%s)" > "$D/relevel.batch"
AT=$MTLS expect "a JSON line of INFO, sent as error" 200 "/ingest" '^kept 1' "${WEB1[@]}" -H "Authorization: Bearer $token" --data-binary @"$D/relevel.batch"
expect "the control: it is found as error" 200 "/search?q=level:error+and+%22relevelme%22" '"roxie-count">1 lines' -b "__Host-wolly=$s2"
(cd "$D" && ./roxie relevel > relevel1.out 2>&1)
r1=$?
check "roxie relevel changes it, and nothing else of the run" bash -c "[ $r1 -eq 0 ] && grep -qE '^roxie: lines read [0-9]+, level changed 1$' '$D/relevel1.out'"
expect "it is no longer found as error" 200 "/search?q=level:error+and+%22relevelme%22" '"roxie-count">0 lines<' -b "__Host-wolly=$s2"
expect "but as info, its text found through the index" 200 "/search?q=level:info+and+%22relevelme%22" '"roxie-count">1 lines' -b "__Host-wolly=$s2"
(cd "$D" && ./roxie relevel > relevel2.out 2>&1)
r2=$?
check "a second relevel changes nothing" bash -c "[ $r2 -eq 0 ] && grep -qE '^roxie: lines read [0-9]+, level changed 0$' '$D/relevel2.out'"
expect "a query refused with its byte marked" 200 "/search?q=level:ERROR" 'a value the field does not take, at byte 6' -b "__Host-wolly=$s2"
expect "a panel alone, as htmx asks for it, asking again" 200 "/panel/lines" '<section class="wolly-panel wolly-bars" id="panel-lines" hx-get="/panel/lines" hx-trigger="every 60s" hx-swap="outerHTML">' -b "__Host-wolly=$s2" -H "HX-Request: true"
expect "a panel that is none" 404 "/panel/nope" 'no such panel' -b "__Host-wolly=$s2"
# Five panels at once, as the dashboard asks every minute: each opens
# the store, and one that meets another rebuilding the WAL was a 500
# (SQLite code 261 in the journal). 30 rounds, every answer 200.
mkdir -p "$D/burst" || exit 9
for ((r = 1; r <= 30; r++)); do
	bp=()
	for p in lines errors batches refused hosts; do
		curl -s -o /dev/null -w '%{http_code}\n' --cacert "$D/config/cert.pem" --max-time 20 -b "__Host-wolly=$s2" "$BASE/panel/$p" > "$D/burst/$r-$p" &
		bp+=("$!")
	done
	wait "${bp[@]}"
done
burst_good=$(cat "$D/burst/"* | grep -cx 200)
echo "five panels at once, 30 rounds: $burst_good of 150 answered 200; $(cat "$D/burst/"* | sort | uniq -c | tr '\n' ' ')"
check "five panels at once, 30 rounds: all 150 answered 200" [ "$burst_good" = 150 ]
check "and the journal names no store that could not be read" bash -c "! grep -q 'could not be read' '$D/roxie.out'"
expect "scripts only of ROXIE, requests only to ROXIE" 200 "/" "^Content-Security-Policy: default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'self'; img-src 'self'; form-action 'self'; frame-ancestors 'none'" -b "__Host-wolly=$s2"
check "the dashboard's head is the h1 the sheet puts the logo before" grep -q '<header class="wolly-head">' "$last.body"
echo "== htmx"
expect "no htmx.min.js in the working directory: 404" 404 "/htmx.min.js" '.'
cp share/htmx.min.js "$D/htmx.min.js" || exit 9
expect "htmx.min.js served as script" 200 "/htmx.min.js" '^Content-Type: text/javascript; charset=utf-8'
check "with a day of cache" grep -q '^Cache-Control: public, max-age=86400' <(tr -d '\r' < "$last.head")
check "the file as it is: htmx 2.0.10, the sha256 of NOTICE" bash -c "[ \$(sha256sum < '$last.body' | cut -c1-64) = 71ea67185bfa8c98c39d31717c6fce5d852370fcdfd129db4543774d3145c0de ] && grep -q 'version:\"2.0.10\"' '$last.body'"
expect "a panel asked by htmx without a session sends the whole page to the login" 200 "/panel/lines" '^HX-Redirect: /login' -H "HX-Request: true"
check "and not the form into the panel" bash -c "! grep -q 'name=\"password\"' '$last.body'"
expect "the same without htmx is the plain redirect" 303 "/panel/lines" '^Location: /login'
expect "HX-Request other than true is no htmx" 303 "/panel/lines" '^Location: /login' -H "HX-Request: True"
# The logout posts the ID token to RAMBO from a page: in a
# redirect it made the address about 4 KB long, and edge answered 503.
expect "logged out: the page that posts to the logout of RAMBO" 200 "/logout" "<form method=\"post\" action=\"https://127\\.0\\.0\\.1:$PORT3/logout\">" -b "__Host-wolly=$s2" --data-raw "csrf=$c2" "${SAME[@]}"
check "no address to RAMBO in a header" bash -c "! grep -qi '^Location:' '$last.head'"
check "the client in the form" grep -q '<input type="hidden" name="client_id" value="roxie">' "$last.body"
check "the ID token as hint in the form" grep -qE '<input type="hidden" name="id_token_hint" value="[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+">' "$last.body"
check "coming back to /signed-out" grep -q "<input type=\"hidden\" name=\"post_logout_redirect_uri\" value=\"https://127.0.0.1:$PORT/signed-out\">" "$last.body"
check "the script that sends it, the one the policy names" grep -q '<script>document.forms\[0\].submit();</script>' "$last.body"
check "a form may post to ROXIE and RAMBO's logout, nowhere else" grep -q "^Content-Security-Policy: default-src 'none'; script-src 'sha256-8lDeP0UDwCO6/RhblgeH/ctdBzjVpJxrXizsnIk3cEQ='; form-action 'self' https://127.0.0.1:$PORT3/logout; base-uri 'none'; frame-ancestors 'none'$" <(tr -d '\r' < "$last.head")
check "the page is not kept" grep -q '^Cache-Control: no-store' <(tr -d '\r' < "$last.head")
check "the session cookie is taken" grep -qi '^Set-Cookie: __Host-wolly=;' <(tr -d '\r' < "$last.head")
expect "the page after the logout" 200 "/signed-out" 'Signed out of ROXIE'
expect "the old session opens nothing" 303 "/" '^Location: /login' -b "__Host-wolly=$s2"

echo "== an account taken back"
expect "a sign-in for a stranger's browser" 303 "/login" "^Location: https://127\\.0\\.0\\.1:$PORT3/authorize\\?"
back=$(curl -s --cacert "$D/config/cert.pem" -o /dev/null -w '%{redirect_url}' --max-time 10 "$(location_of)")
expect "its callback without the session that began it is refused" 400 "${back#"$BASE"}" 'unknown here'
(cd "$D" && ./roxie revoke-user ann > revoke-user.out 2>&1)
check "roxie revoke-user ann" grep -qx "roxie: accounts no more allowed: 1" "$D/revoke-user.out"
expect "a sign-in begins" 303 "/login" "^Location: https://127\\.0\\.0\\.1:$PORT3/authorize\\?"
s3=$(cookie_of)
back=$(curl -s --cacert "$D/config/cert.pem" -o /dev/null -w '%{redirect_url}' --max-time 10 "$(location_of)")
expect "the account RAMBO vouches for opens nothing now" 403 "${back#"$BASE"}" 'not allowed here' -b "__Host-wolly=$s3"
(cd "$D" && ./roxie allow ann "$ANN_SUB" > allow-again.out 2>&1)
check "allowed again" grep -qx "roxie: the account is allowed" "$D/allow-again.out"
expect "a sign-in begins again" 303 "/login" "^Location: https://127\\.0\\.0\\.1:$PORT3/authorize\\?"
s4=$(cookie_of)
back=$(curl -s --cacert "$D/config/cert.pem" -o /dev/null -w '%{redirect_url}' --max-time 10 "$(location_of)")
expect "and opens a session" 303 "${back#"$BASE"}" '^Location: /$' -b "__Host-wolly=$s4"
s5=$(cookie_of)
expect "the dashboard of the session" 200 "/" 'id="panel-lines"' -b "__Host-wolly=$s5"
expect "no second factor of ROXIE any more" 404 "/totp" '.' -b "__Host-wolly=$s5"
expect "no form for a password any more" 405 "/login" '.' --data-raw "name=ann&password=x" "${SAME[@]}"
echo "== the command line"
# The build of the gate has the version v9.8.7-3-gabcdef1 (scripts/in-gate.sh).
run_roxie() { local name=$1; shift; (cd "$D" && ./roxie "$@" > "$D/cli-$name.out" 2> "$D/cli-$name.err"); echo $? > "$D/cli-$name.rc"; }
rc_of() { cat "$D/cli-$1.rc"; }
run_roxie version-long --version
check "--version: one line, name, number without its v, copyright" bash -c "[ $(rc_of version-long) -eq 0 ] && [ \"\$(cat '$D/cli-version-long.out')\" = 'roxie 9.8.7, Copyright (C) 2026 Heiko Zimmermann' ]"
run_roxie version-short -V
check "-V the same" cmp -s "$D/cli-version-long.out" "$D/cli-version-short.out"
run_roxie version-word version
check "version the same" cmp -s "$D/cli-version-long.out" "$D/cli-version-word.out"
run_roxie version-full version --full
check "version --full: the version, the commit, the build, the copyright last" bash -c "grep -qE '^version +9\\.8\\.7\$' '$D/cli-version-full.out' && grep -qE '^commit ' '$D/cli-version-full.out' && grep -qE '^built ' '$D/cli-version-full.out' && tail -1 '$D/cli-version-full.out' | grep -qE '^copyright +Copyright \\(C\\) 2026 Heiko Zimmermann$' || { sed 's/^/      out /' '$D/cli-version-full.out' '$D/cli-version-full.err'; cat '$D/cli-version-full.rc'; false; }"
check "no sandbox in version --full" bash -c "! grep -qi 'sandbox' '$D/cli-version-full.out'"
run_roxie info info
check "info: the banner, the words of the name, the name and its version" bash -c "[ \$(cat '$D/cli-info.rc') -eq 0 ] && grep -qF ' ####   ###  #   # ##### #####' '$D/cli-info.out' && grep -qF 'Ranked Objects eXtended Index Engine' '$D/cli-info.out' && grep -qE '9\\.8\\.7' '$D/cli-info.out'"
run_roxie help -h
check "-h names query and doctor" bash -c "[ \$(cat '$D/cli-help.rc') -eq 0 ] && grep -q 'query' '$D/cli-help.out' && grep -q 'doctor' '$D/cli-help.out'"
run_roxie help-query help query
check "help query names --limit and --since" bash -c "grep -q -- '--limit' '$D/cli-help-query.out' && grep -q -- '--since' '$D/cli-help-query.out'"
run_roxie mistyped qeury host:server
check "a word nearly right: refused, and the word meant named" bash -c "[ \$(cat '$D/cli-mistyped.rc') -ne 0 ] && grep -q 'query' '$D/cli-mistyped.err' && [ ! -s '$D/cli-mistyped.out' ]"
run_roxie sandbox -s
check "-s says what confines the process" bash -c "[ \$(cat '$D/cli-sandbox.rc') -eq 0 ] && grep -q '^sandbox: ' '$D/cli-sandbox.out' && grep -q '^no new privs: ' '$D/cli-sandbox.out' && grep -q '^seccomp: ' '$D/cli-sandbox.out'"
run_roxie sandbox-word sandbox
check "sandbox the same" cmp -s "$D/cli-sandbox.out" "$D/cli-sandbox-word.out"
run_roxie completion setup completion bash
check "setup completion bash: a script of bash for roxie" bash -c "[ \$(cat '$D/cli-completion.rc') -eq 0 ] && grep -q 'complete' '$D/cli-completion.out' && grep -q 'roxie' '$D/cli-completion.out' && bash -n '$D/cli-completion.out'"
run_roxie manual setup manual
check "setup manual: a page of mdoc of its date" bash -c "[ \$(cat '$D/cli-manual.rc') -eq 0 ] && grep -qx '.Dd October 22, 2026' '$D/cli-manual.out' && grep -q '^\\.Nm roxie' '$D/cli-manual.out'"
run_roxie doctor --socket "$D/run/roxie.sock" doctor
check "doctor: every file of the run there, success" bash -c "[ \$(cat '$D/cli-doctor.rc') -eq 0 ] && ! grep -qi 'missing' '$D/cli-doctor.out' && grep -q 'RAMBO secret' '$D/cli-doctor.out' && grep -q 'socket' '$D/cli-doctor.out' || { sed 's/^/      /' '$D/cli-doctor.out'; false; }"
run_roxie doctor-json --json --socket "$D/run/roxie.sock" doctor
check "doctor --json is JSON" python3 -I -c 'import json, sys; json.load(open(sys.argv[1]))' "$D/cli-doctor-json.out"
mkdir -p "$D/empty" && (cd "$D/empty" && ../roxie --socket "$D/empty/none.sock" doctor > ../cli-doctor-empty.out 2>&1; echo $? > ../cli-doctor-empty.rc)
check "doctor in an empty directory: failure, each file missing with its fix" bash -c "[ \$(cat '$D/cli-doctor-empty.rc') -ne 0 ] && [ \$(grep -ci 'missing' '$D/cli-doctor-empty.out') -ge 8 ] && grep -q 'rambo-secret.sh' '$D/cli-doctor-empty.out'"
chmod 644 "$D/rambo-secret"
run_roxie doctor-open --socket "$D/run/roxie.sock" doctor
chmod 600 "$D/rambo-secret"
check "doctor: a secret others may read is a failure" bash -c "[ \$(cat '$D/cli-doctor-open.rc') -ne 0 ] && grep -q 'others than its owner may read it' '$D/cli-doctor-open.out'"
expect "the search page of the same query, for its count" 200 "/search?q=host:web1.example.org+and+level:error" 'roxie-count' -b "__Host-wolly=$s5"
errors_web1=$(sed -n 's/.*"roxie-count">\([0-9]*\) lines.*/\1/p' "$last.body" | head -1)
check "the page counts the error lines of web1" bash -c "[ -n '$errors_web1' ] && [ '$errors_web1' -ge 2 ]"
run_roxie query-text query host:web1.example.org and level:error
check "query: the lines as text, as many as the page counts, time, host, level, source, text between tabs" bash -c "[ \$(cat '$D/cli-query-text.rc') -eq 0 ] && [ \$(wc -l < '$D/cli-query-text.out') -eq $errors_web1 ] && grep -qP '^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ\\tweb1\\.example\\.org\\terror\\t[^\\t]+\\t.*crashed' '$D/cli-query-text.out'"
run_roxie query-json --json query host:web1.example.org and level:error
check "query --json: schema 1, every field of every line in its type (docs/syntax.md)" python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert list(d) == ["schema", "version", "query", "now", "total", "shown", "lines"], list(d)
assert d["schema"] == 1 and d["version"] == "9.8.7" and d["query"] == "host:web1.example.org and level:error"
n = int(sys.argv[2])
assert isinstance(d["now"], int) and d["total"] == n and d["shown"] == n and len(d["lines"]) == n, (d["total"], n)
for l in d["lines"]:
    assert list(l) == ["id", "at", "time", "host", "source", "level", "line"], list(l)
    assert isinstance(l["id"], int) and isinstance(l["at"], int) and l["host"] == "web1.example.org" and l["level"] == "error"
    assert all(isinstance(l[k], str) for k in ("time", "source", "line"))
assert all(a["at"] >= b["at"] for a, b in zip(d["lines"], d["lines"][1:]))
' "$D/cli-query-json.out" "$errors_web1"
run_roxie query-limit --json query --limit 1 host:web1.example.org and level:error
check "--limit 1: one of them shown, the total the page counts" python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d["total"] == int(sys.argv[2]) and d["shown"] == 1 and len(d["lines"]) == 1' "$D/cli-query-limit.out" "$errors_web1"
run_roxie query-all --json query host:web1.example.org
run_roxie query-since --json query --since 24h host:web1.example.org
check "--since 24h leaves the lines of 2026-10-01 and of the BSD form out" python3 -I -c '
import json, sys
a, s = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
assert s["query"] == "(host:web1.example.org) and time:last 24h", s["query"]
assert any(l["time"].startswith("2026-10-01") for l in a["lines"])
assert any(l["time"].startswith(sys.argv[3]) for l in a["lines"])
assert s["total"] == a["total"] - 3 and not any(l["time"].startswith(("2026-10-01", sys.argv[3])) for l in s["lines"])
' "$D/cli-query-all.out" "$D/cli-query-since.out" "$bsd_day"
run_roxie query-day --json query --since 2026-10-01 host:web1.example.org
check "--since a day: from that day on" python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d["query"].startswith("(host:web1.example.org) and time:[2026-10-01 .. ") and d["total"] >= 2' "$D/cli-query-day.out"
run_roxie query-none --json query host:nobody.example.org
check "nothing found: success, total 0, no lines" bash -c "[ \$(cat '$D/cli-query-none.rc') -eq 0 ] && python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d[\"total\"] == 0 and d[\"lines\"] == []' '$D/cli-query-none.out'"
run_roxie query-refused --json query level:ERROR
check "a refused query: exit 2, the error as JSON with its byte, why to standard error" bash -c "[ \$(cat '$D/cli-query-refused.rc') -eq 2 ] && python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d[\"error\"] == {\"kind\": \"refused\", \"problem\": \"a value the field does not take\", \"position\": 6}' '$D/cli-query-refused.out' && grep -q 'at byte 6' '$D/cli-query-refused.err'"
run_roxie query-since-bad --json query --since 24x host:server
check "a refused --since: exit 2, error since" bash -c "[ \$(cat '$D/cli-query-since-bad.rc') -eq 2 ] && python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d[\"error\"][\"kind\"] == \"since\" and d[\"error\"][\"position\"] is None' '$D/cli-query-since-bad.out'"
run_roxie query-empty query
check "query without QUERY: exit 1, refused by the command line" bash -c "[ \$(cat '$D/cli-query-empty.rc') -eq 1 ] && [ -s '$D/cli-query-empty.err' ] && [ ! -s '$D/cli-query-empty.out' ]"
run_roxie query-limit-bad query --limit 101 host:server
check "--limit 101 refused, exit 1" bash -c "[ \$(cat '$D/cli-query-limit-bad.rc') -eq 1 ] && grep -q 'limit' '$D/cli-query-limit-bad.err'"
mkdir -p "$D/nostore" && (cd "$D/nostore" && ../roxie --json query host:server > ../cli-query-nostore.out 2> ../cli-query-nostore.err; echo $? > ../cli-query-nostore.rc)
check "query in a directory without the store: exit 4, error storage" bash -c "[ \$(cat '$D/cli-query-nostore.rc') -eq 4 ] && python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d[\"error\"][\"kind\"] == \"storage\"' '$D/cli-query-nostore.out'"

echo "== retention"
(cd "$D" && ./roxie prune 0 > prune0.out 2>&1)
check "a prune of 0 days is refused" grep -q "refused: DAYS" "$D/prune0.out"
printf '%s\n' '{"time":"2024-10-13T23:59:59.000Z","level":"info","msg":"login","user":"old","client":"-","outcome":"ok"}' >> "$D/audit.log"
audit_before=$(wc -l < "$D/audit.log")
(cd "$D" && ./roxie prune 1 > prune1.out 2>&1)
p1=$?
check "a prune of a day takes the two lines of 2026-10-01, the one of the BSD form and nothing of today" bash -c "[ $p1 -eq 0 ] && grep -q 'lines pruned 3, samples pruned 0' '$D/prune1.out'"
check "and the audit line of 2024 with Wolly.AuditLog, the lines of today stay" bash -c "grep -q 'audit lines pruned 1$' '$D/prune1.out' && [ \$(wc -l < '$D/audit.log') -eq $((audit_before - 1)) ] && ! grep -q '\"user\":\"old\"' '$D/audit.log' && grep -q '\"msg\":\"login-external\"' '$D/audit.log' || { sed 's/^/      prune /' '$D/prune1.out'; tail -3 '$D/audit.log' | sed 's/^/      audit /'; echo \"      before $audit_before after \$(wc -l < '$D/audit.log')\"; false; }"
expect "and the lines are still found" 200 "/style.css" '.'

# The agent that keeps running names what confines it; the
# rounds above ran confined as well, or they would have ended with 1.
echo "== the agent that keeps running, confined"
# Its log and its state each in a directory of their own, so that the
# directory of the state, granted rwc, does not hold the log as well.
mkdir -p "$D/run-agent/logs" "$D/run-agent/state" && : > "$D/run-agent/logs/app.log" || exit 9
printf '%s\n' "collector $MTLS/ingest" "ca $D/config/cert.pem" "certificate $D/config/web1.example.org.pem" "key $D/config/web1.example.org.key" \
	"token $D/token" "state $D/run-agent/state/agent.db" "every 1" "report 0" "file $D/run-agent/logs/app.log" > "$D/run-agent.conf"
(cd "$D" && exec ./roxie agent run-agent.conf > agent-run.out 2>&1) &
runner=$!
for ((i = 1; i <= 600; i++)); do
	grep -q '^roxie agent: sandbox: ' "$D/agent-run.out" 2> /dev/null && break
	kill -0 "$runner" 2> /dev/null || break
	sleep 0.1
done
# A line, then the log rotated to a new file of the same name and a line
# there: confined, the agent still reaches the new file (Confine grants
# the directory, Landlock would hold a granted file by its old inode).
printf '%s\n' "before the rotation" >> "$D/run-agent/logs/app.log"
for ((i = 1; i <= 600; i++)); do grep -q '^roxie agent: lines 1, batches taken 1' "$D/agent-run.out" && break; sleep 0.1; done
mv "$D/run-agent/logs/app.log" "$D/run-agent/logs/app.log.1" && printf '%s\n' "after the rotation" > "$D/run-agent/logs/app.log"
for ((i = 1; i <= 600; i++)); do [ "$(grep -c '^roxie agent: lines 1, batches taken 1' "$D/agent-run.out")" -ge 2 ] && break; sleep 0.1; done
kill -TERM "$runner" 2> /dev/null
wait "$runner"
ar=$?
cat "$D/agent-run.out"
check "the agent that keeps running names what confines it" grep -qE '^roxie agent: sandbox: +[a-z]' "$D/agent-run.out"
check "confined, it sends a line before and one after the log is rotated" bash -c "[ \$(grep -c '^roxie agent: lines 1, batches taken 1' '$D/agent-run.out') -eq 2 ] && ! grep -q 'files not read' '$D/agent-run.out'"
check "it runs confined" bash -c "! grep -q 'nothing confines' '$D/agent-run.out'"
check "it stops on SIGTERM with 0" bash -c "[ $ar -eq 0 ] && grep -qx 'roxie agent: stopped' '$D/agent-run.out'"
# Its state is new, and the agent-once runs of the same host numbered their
# batches from 1 before it: a new state numbers above the time in
# milliseconds (Roxie.Outbox.startNumbersAt), or the collector would answer
# its batches as sent already and keep none of them.
(cd "$D" && ./roxie query '"after the rotation"' > run-query.out 2>&1)
check "the lines of an agent with a new state arrive, though its host sent batches before" bash -c "grep -q 'after the rotation' '$D/run-query.out' || { sed 's/^/      query /' '$D/run-query.out'; false; }"

# Rounds that went well are said together every report seconds, 600 when
# the setting is left out: the first round that sent a line at once, the
# next one within the 600 seconds not, though its line arrives.
echo "== the agent that keeps running says its rounds together"
mkdir -p "$D/quiet-agent/logs" "$D/quiet-agent/state" && : > "$D/quiet-agent/logs/app.log" || exit 9
printf '%s\n' "collector $MTLS/ingest" "ca $D/config/cert.pem" "certificate $D/config/web1.example.org.pem" "key $D/config/web1.example.org.key" \
	"token $D/token" "state $D/quiet-agent/state/agent.db" "every 1" "file $D/quiet-agent/logs/app.log" > "$D/quiet-agent.conf"
(cd "$D" && exec ./roxie agent quiet-agent.conf > agent-quiet.out 2>&1) &
quiet=$!
printf '%s\n' "quietfirst line of the agent" >> "$D/quiet-agent/logs/app.log"
for ((i = 1; i <= 600; i++)); do grep -q '^roxie agent: lines 1, batches taken 1' "$D/agent-quiet.out" 2> /dev/null && break; sleep 0.1; done
printf '%s\n' "quietsecond line of the agent" >> "$D/quiet-agent/logs/app.log"
for ((i = 1; i <= 600; i++)); do
	(cd "$D" && ./roxie query '"quietsecond"' > quiet-query.out 2>&1; echo "query-rc=$?" >> quiet-query.out)
	grep -q 'quietsecond line of the agent' "$D/quiet-query.out" && break
	sleep 0.1
done
sleep 2
kill -TERM "$quiet" 2> /dev/null
wait "$quiet"
qr=$?
cat "$D/agent-quiet.out"
check "report left out: the first round that sent a line is said at once" grep -q '^roxie agent: lines 1, batches taken 1, set aside 0$' "$D/agent-quiet.out"
check "and the next round within 600 seconds is not, though its line arrived" bash -c "[ \$(grep -c '^roxie agent: lines' '$D/agent-quiet.out') -eq 1 ] && grep -q 'quietsecond line of the agent' '$D/quiet-query.out' && [ $qr -eq 0 ] || { sed 's/^/      query /' '$D/quiet-query.out'; (cd '$D' && ./roxie query --limit 5 host:web1.example.org; ./roxie query '\"quietfirst\"') 2>&1 | sed 's/^/      diag /'; false; }"

echo "== roxie stopped"
kill -TERM "$app"
wait "$app"
app_exit=$?
check "roxie ends with 0 on TERM" [ "$app_exit" -eq 0 ]
expect "the control: without roxie Hiawatha answers 503" 503 "/login" '.'
expect "and the stylesheet still comes: it is Hiawatha's file" 200 "/style.css" 'wolly-panel'
kill -TERM "$web" 2> /dev/null
wait "$web" 2> /dev/null
echo "e2e: cases=$cases good=$good"
[ "$good" -eq "$cases" ]
