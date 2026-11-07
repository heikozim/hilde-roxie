"""The stand-in of the collector's /ingest for the install test on OpenBSD
(scripts/in-bsd-install.sh), where SQLCipher has no FTS5 and the
collector does not run: HTTPS on ADDRESS:PORT with CERT and KEY, a client
certificate of CA required, its CN must be NAME and the bearer the token
in TOKEN.  A batch it takes is answered 200 and its lines are appended to
RECORD, one a line; anything else is 403 or 400 and goes nowhere.

    python3 -I scripts/ingest-standin.py ADDRESS PORT CERT KEY CA NAME TOKEN RECORD
"""

import http.server
import ssl
import sys

address, port, cert, key, ca, name, token_file, record = sys.argv[1:9]
with open(token_file, encoding="ascii") as f:
    token = f.read().strip()


class Ingest(http.server.BaseHTTPRequestHandler):
    def answer(self, status, text):
        body = text.encode("ascii")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        peer = self.connection.getpeercert() or {}
        cn = [v for rdn in peer.get("subject", ()) for k, v in rdn if k == "commonName"]
        if self.path != "/ingest" or cn != [name] or self.headers.get("Authorization") != "Bearer " + token:
            self.answer(403, "forbidden\n")
            return
        size = int(self.headers.get("Content-Length", "0"))
        if size <= 0 or size > 1048576:
            self.answer(400, "size\n")
            return
        lines = self.rfile.read(size).decode("utf-8", "replace").split("\n")
        if not lines[0].startswith("roxie 1 "):
            self.answer(400, "head\n")
            return
        with open(record, "a", encoding="utf-8") as f:
            for line in lines[1:]:
                if line:
                    f.write(line + "\n")
        self.answer(200, "taken\n")

    def log_message(self, form, *args):
        sys.stderr.write("standin: " + (form % args) + "\n")


context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(cert, key)
context.load_verify_locations(ca)
context.verify_mode = ssl.CERT_REQUIRED
server = http.server.HTTPServer((address, int(port)), Ingest)
# The handshake on the first read, in the request: a connection without
# TLS, such as a probe of the port, fails alone and not the server.
server.socket = context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
server.serve_forever()
