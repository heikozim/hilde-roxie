"""A stand-in for RAMBO in ROXIE's end to end: the paths of
Wolly.Rambo under one issuer (/authorize, /token, /jwks, /logout), over
HTTPS with the certificate of the run, ID tokens signed with ML-DSA-44 by
OpenSSL (3.5 or later).  It signs every sign-in in as the account of its
second argument and checks what RAMBO checks of the client: the client id,
the secret by Basic, the redirect, the PKCE verifier against its challenge,
a code taken once.

    python3 -I rambo-standin.py PORT SUB CLIENT SECRET CERT KEY WORKDIR

Not a part of ROXIE: it runs only inside scripts/in-e2e.sh.
"""
import base64
import hashlib
import http.server
import json
import os
import secrets
import ssl
import subprocess
import sys
import time
import urllib.parse

port, sub, client, secret, cert, key, work = sys.argv[1:8]
issuer = "https://127.0.0.1:%s" % port
codes = {}
signing = os.path.join(work, "rambo-mldsa.pem")
subprocess.run(["openssl", "genpkey", "-algorithm", "ML-DSA-44", "-out", signing], check=True)
der = subprocess.run(["openssl", "pkey", "-in", signing, "-pubout", "-outform", "DER"], check=True, capture_output=True).stdout


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


jwks = json.dumps({"keys": [{"kty": "AKP", "alg": "ML-DSA-44", "kid": "k1", "pub": b64(der[22:])}]}).encode()


def sign(payload):
    head = b64(json.dumps({"alg": "ML-DSA-44", "kid": "k1", "typ": "JWT"}).encode())
    body = b64(json.dumps(payload).encode())
    data = ("%s.%s" % (head, body)).encode()
    path = os.path.join(work, "rambo-input")
    with open(path, "wb") as f:
        f.write(data)
    sig = subprocess.run(["openssl", "pkeyutl", "-sign", "-inkey", signing, "-rawin", "-in", path], check=True, capture_output=True).stdout
    return "%s.%s" % (data.decode(), b64(sig))


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        sys.stderr.write("rambo-standin: %s\n" % (args[0] % args[1:]))

    def answer(self, status, body, kind="application/json", location=None):
        self.send_response(status)
        if location:
            self.send_header("Location", location)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        q = dict(urllib.parse.parse_qsl(url.query))
        if url.path == "/jwks":
            return self.answer(200, jwks)
        if url.path == "/authorize":
            if q.get("client_id") != client or q.get("response_type") != "code" or q.get("code_challenge_method") != "S256":
                return self.answer(400, b'{"error":"invalid_request"}')
            code = secrets.token_urlsafe(24)
            codes[code] = (q.get("nonce", ""), q.get("code_challenge", ""), q.get("redirect_uri", ""))
            back = "%s?%s" % (q["redirect_uri"], urllib.parse.urlencode({"code": code, "state": q.get("state", ""), "iss": issuer}))
            return self.answer(302, b"", "text/plain", back)
        if url.path == "/logout":
            return self.answer(302, b"", "text/plain", q.get("post_logout_redirect_uri", issuer))
        return self.answer(404, b'{"error":"not_found"}')

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        form = dict(urllib.parse.parse_qsl(self.rfile.read(length).decode()))
        if self.path != "/token":
            return self.answer(404, b'{"error":"not_found"}')
        want = "Basic " + base64.b64encode(("%s:%s" % (client, secret)).encode()).decode()
        if self.headers.get("Authorization") != want:
            return self.answer(401, b'{"error":"invalid_client"}')
        found = codes.pop(form.get("code", ""), None)
        if not found or form.get("grant_type") != "authorization_code":
            return self.answer(400, b'{"error":"invalid_grant"}')
        nonce, challenge, redirect = found
        if form.get("redirect_uri", redirect) != redirect or b64(hashlib.sha256(form.get("code_verifier", "").encode()).digest()) != challenge:
            return self.answer(400, b'{"error":"invalid_grant"}')
        now = int(time.time())
        token = sign({"iss": issuer, "sub": sub, "aud": client, "azp": client, "iat": now, "exp": now + 300,
                      "auth_time": now, "nonce": nonce, "name": "Ann of the end to end"})
        body = json.dumps({"access_token": secrets.token_urlsafe(24), "token_type": "Bearer", "id_token": token, "expires_in": 300})
        return self.answer(200, body.encode())


server = http.server.HTTPServer(("127.0.0.1", int(port)), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(cert, key)
server.socket = context.wrap_socket(server.socket, server_side=True)
sys.stderr.write("rambo-standin: %s ready\n" % issuer)
sys.stderr.flush()
server.serve_forever()
