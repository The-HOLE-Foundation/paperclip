#!/bin/sh
# Self-test for infisical-bootstrap.sh against a mock Infisical API.
#   sh scripts/hole/infisical-bootstrap.test.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
port=18765
tmp="$(mktemp -d)"
mock=
trap 'rc=$?; [ "$rc" -eq 0 ] || cat "$tmp"/err* >&2 2>/dev/null; [ -z "$mock" ] || kill "$mock" 2>/dev/null; rm -rf "$tmp"' EXIT

node -e '
const http = require("node:http");
http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  if (req.method === "POST" && url.pathname === "/api/v1/auth/universal-auth/login") {
    let body = ""; req.on("data", (c) => body += c); req.on("end", () => {
      const p = new URLSearchParams(body);
      if (p.get("clientSecret") !== "good") { res.writeHead(401); return res.end("{}"); }
      res.end(JSON.stringify({ accessToken: "tok" }));
    });
    return;
  }
  if (url.pathname === "/api/v4/secrets" && req.headers.authorization === "Bearer tok"
      && url.searchParams.get("secretPath") === "/bootstrap") {
    return res.end(JSON.stringify({ secrets: [
      { secretKey: "FROM_INFISICAL", secretValue: "it'"'"'s a \"value\" with $HOME\nand a newline" },
      { secretKey: "ALREADY_SET", secretValue: "infisical" },
      { secretKey: "EMPTY_ON_HOST", secretValue: "filled" },
      { secretKey: "bad-key", secretValue: "x" },
    ] }));
  }
  res.writeHead(404); res.end("{}");
}).listen('"$port"', "127.0.0.1");
' &
mock=$!
# Bounded wait; a mock that died (e.g. port taken) fails fast instead of hanging.
i=0
until curl -s -o /dev/null "http://127.0.0.1:$port/"; do
  kill -0 "$mock" 2>/dev/null || { echo "mock server exited" >&2; exit 1; }
  i=$((i + 1)); [ "$i" -lt 50 ] || { echo "mock server not ready" >&2; exit 1; }
  sleep 0.2
done
kill -0 "$mock" 2>/dev/null || { echo "mock server exited" >&2; exit 1; }

export INFISICAL_API_URL="http://127.0.0.1:$port" INFISICAL_CLIENT_ID=id INFISICAL_PROJECT_ID=p

# 1. Loads secrets; non-empty env wins; empty env is filled; invalid keys skipped; values exact.
INFISICAL_CLIENT_SECRET=good ALREADY_SET=host EMPTY_ON_HOST= PAPERCLIP_REQUIRED_ENV="FROM_INFISICAL" \
  sh "$here/infisical-bootstrap.sh" node -e '
    const e = process.env, assert = require("node:assert/strict");
    assert.equal(e.FROM_INFISICAL, "it'"'"'s a \"value\" with $HOME\nand a newline");
    assert.equal(e.ALREADY_SET, "host");
    assert.equal(e.EMPTY_ON_HOST, "filled");
    assert.equal(e.INFISICAL_CLIENT_SECRET, undefined);
  ' 2>"$tmp/err1"
echo "ok 1 loads secrets"

# 2. Required env missing -> refuse to start.
if INFISICAL_CLIENT_SECRET=good PAPERCLIP_REQUIRED_ENV="FROM_INFISICAL DATABASE_URL" \
  sh "$here/infisical-bootstrap.sh" true 2>"$tmp/err2"; then echo "not ok 2: started"; exit 1; fi
grep -q "required env missing: DATABASE_URL" "$tmp/err2"
echo "ok 2 refuses on missing required env"

# 3. Bad credentials -> refuse to start (never boot without the secrets).
if INFISICAL_CLIENT_SECRET=bad sh "$here/infisical-bootstrap.sh" true 2>"$tmp/err3"; then echo "not ok 3: started"; exit 1; fi
grep -q "login failed" "$tmp/err3"
echo "ok 3 refuses on Infisical auth failure"

# 4. Infisical not configured -> skip, still exec.
INFISICAL_CLIENT_SECRET= sh "$here/infisical-bootstrap.sh" true 2>"$tmp/err4"
grep -q "skipping Infisical" "$tmp/err4"
echo "ok 4 skips when unconfigured"
