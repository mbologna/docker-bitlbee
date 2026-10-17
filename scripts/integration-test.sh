#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE_REF:-${DOCKER_USERNAME}/docker-bitlbee:latest}"

docker pull "$IMAGE"

# Polls a container's Docker healthcheck until "healthy", up to 45*2=90s.
# Exits (with logs) if the container stops or never turns healthy.
wait_healthy() {
  local name="$1" status="gone"
  for i in {1..45}; do
    status=$(docker inspect --format="{{.State.Health.Status}}" "$name" 2>/dev/null || echo "gone")
    local running
    running=$(docker inspect --format="{{.State.Running}}" "$name" 2>/dev/null || echo "false")
    if [ "$running" != "true" ]; then
      echo "Container stopped unexpectedly"
      docker logs "$name"
      docker rm "$name" || true
      exit 1
    fi
    if [ "$status" = "healthy" ]; then
      echo "Container is healthy"
      return 0
    fi
    echo "Waiting... ($i/45) [status=$status]"
    sleep 2
  done
  echo "Container failed to become healthy"
  docker logs "$name"
  docker rm "$name" || true
  exit 1
}

docker run -d --name bitlbee-test \
  -p 6697:6697 \
  -p 6698:6698 \
  -p 6699:6699 \
  -e UID=1000 -e GID=1000 \
  -e MATRIX_REGISTRATION_TOKEN=ci-test-token \
  "$IMAGE"

wait_healthy bitlbee-test

# The healthcheck only probes ports; a failed first-run init (e.g. the
# mautrix-meta appservice never registered with conduwuit) leaves them open.
# (Logs captured first: grep -q closing the pipe early would trip pipefail.)
init_logs=$(docker logs bitlbee-test 2>&1)
if ! grep -q '10-init.sh exited 0' <<<"$init_logs"; then
  echo "FAIL: first-run init did not succeed"
  docker logs bitlbee-test; docker rm -f bitlbee-test; exit 1
fi
echo "First-run init OK"

timeout 10s docker exec bitlbee-test nc -zv localhost 6697 || exit 1
echo "IRC TLS port 6697 OK"

echo "=== Verifying plugin files ==="
PURPLE_DIR=$(docker exec bitlbee-test find /usr/lib -maxdepth 3 -name "purple-2" -type d | head -1)
BITLBEE_PLUGIN_DIR="/usr/local/lib/bitlbee"

PURPLE_PLUGINS="libdiscord.so libteams.so libgooglechat.so libwhatsmeow.so libtelegram-tdlib.so"
BITLBEE_PLUGINS="mastodon.so"

for plugin in $PURPLE_PLUGINS; do
  docker exec bitlbee-test test -f "${PURPLE_DIR}/${plugin}" \
    || { echo "FAIL: missing purple plugin ${plugin}"; docker logs bitlbee-test; docker rm -f bitlbee-test; exit 1; }
  echo "  ok ${plugin}"
done
for plugin in $BITLBEE_PLUGINS; do
  docker exec bitlbee-test test -f "${BITLBEE_PLUGIN_DIR}/${plugin}" \
    || { echo "FAIL: missing bitlbee plugin ${plugin}"; docker logs bitlbee-test; docker rm -f bitlbee-test; exit 1; }
  echo "  ok ${plugin}"
done
echo "All plugin files present"

echo "=== Verifying BitlBee plugin list over IRC/TLS ==="
python3 - <<'PYEOF'
import ssl, socket, time, sys

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

buf = b""
with socket.create_connection(("localhost", 6697), timeout=15) as sock:
    with ctx.wrap_socket(sock) as s:
        s.sendall(b"NICK ci-plugin-test\r\nUSER ci-plugin-test 0 * :CI\r\n")
        time.sleep(2)
        s.sendall(b"PRIVMSG &bitlbee :plugins\r\n")
        time.sleep(3)
        s.settimeout(2)
        try:
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                buf += chunk
        except socket.timeout:
            pass

output = buf.decode("utf-8", errors="replace")
print(output)
if "purple" not in output.lower():
    print("FAIL: BitlBee did not report purple plugin", file=sys.stderr)
    sys.exit(1)
PYEOF
echo "IRC/TLS plugin check OK"

echo "=== Verifying Matrix over IRC/TLS (matrix2051 on 6698) ==="
timeout 10s docker exec bitlbee-test nc -zv localhost 6698 || exit 1
echo "IRC TLS port 6698 OK"

# matrix2051's plaintext port must only be reachable on loopback
if docker exec bitlbee-test sh -c 'nc -z "$(hostname -i | cut -d" " -f1)" 2051'; then
  echo "FAIL: matrix2051 plaintext port 2051 is reachable outside loopback"
  docker logs bitlbee-test; docker rm -f bitlbee-test; exit 1
fi
echo "matrix2051 plaintext port is loopback-only"

docker exec bitlbee-test matrix-register ci ci-pass \
  || { echo "FAIL: matrix-register"; docker logs bitlbee-test; docker rm -f bitlbee-test; exit 1; }

# SASL login as @ci:localhost on the built-in homeserver, then wait for the
# bridge chat created by matrix-register to be listed with the bridge bot in
# it: this exercises stunnel -> matrix2051 -> conduwuit -> mautrix-meta.
python3 - <<'PYEOF2'
import base64, ssl, socket, time, sys

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def lines_until(s, buf, pred, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if pred(buf.decode("utf-8", errors="replace")):
            return buf, True
        s.settimeout(max(0.1, deadline - time.time()))
        try:
            chunk = s.recv(4096)
        except socket.timeout:
            break
        if not chunk:
            break
        buf += chunk
    return buf, pred(buf.decode("utf-8", errors="replace"))

auth = base64.b64encode(b"\0ci:localhost\0ci-pass")
with socket.create_connection(("localhost", 6698), timeout=15) as sock:
    with ctx.wrap_socket(sock) as s:
        s.sendall(b"CAP LS 302\r\nNICK ci\r\n"
                  b"USER ci 0 * :homeserver-url=http://127.0.0.1:6167\r\n"
                  b"CAP REQ :sasl\r\nAUTHENTICATE PLAIN\r\n")
        buf, ok = lines_until(s, b"", lambda o: "AUTHENTICATE +" in o, 15)
        s.sendall(b"AUTHENTICATE " + auth + b"\r\nCAP END\r\n")
        buf, ok = lines_until(s, buf, lambda o: " 903 " in o or " 904 " in o, 30)
        if not (ok and " 903 " in buf.decode()):
            print(buf.decode("utf-8", errors="replace"))
            print("FAIL: SASL login to matrix2051 failed", file=sys.stderr)
            sys.exit(1)
        buf, ok = lines_until(
            s, buf,
            lambda o: "JOIN :#facebook-ci:localhost" in o and "facebookbot" in o, 60)

output = buf.decode("utf-8", errors="replace")
print(output)
if not ok:
    print("FAIL: bridge chat not listed, or the bridge bot is not in it", file=sys.stderr)
    sys.exit(1)
PYEOF2
echo "Matrix over IRC/TLS check OK"

echo "=== Verifying BitlBee from Matrix (heisenbridge, client API on 6699) ==="
# As @ci:localhost over the TLS client API: DM the heisenbridge bot, add
# BitlBee as a network, connect, and wait for BitlBee's greeting to come back
# through the bridge.
python3 - <<'PYEOF2'
import json, ssl, sys, time, urllib.parse, urllib.request

BASE = "https://localhost:6699"
USER, PASSWORD = "ci", "ci-pass"
BOT = "@heisenbridge:localhost"
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE
token = None
txn = 0


def api(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method,
                                 data=None if body is None else json.dumps(body).encode())
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, context=CTX, timeout=40) as r:
        return json.load(r)


def say(room, text):
    global txn
    txn += 1
    api("PUT", f"/_matrix/client/v3/rooms/{urllib.parse.quote(room)}/send/m.room.message/t{time.time_ns()}{txn}",
        {"msgtype": "m.text", "body": text})


since = None


def sync():
    global since
    q = {"timeout": "5000"}
    if since:
        q["since"] = since
    r = api("GET", "/_matrix/client/v3/sync?" + urllib.parse.urlencode(q))
    since = r["next_batch"]
    return r


def wait_for(pred, what, timeout=60):
    end = time.time() + timeout
    while time.time() < end:
        hit = pred(sync())
        if hit:
            return hit
    print(f"FAIL: timed out waiting for {what}", file=sys.stderr)
    sys.exit(1)


def messages(r, room=None):
    for rid, data in r.get("rooms", {}).get("join", {}).items():
        if room and rid != room:
            continue
        for ev in data.get("timeline", {}).get("events", []):
            if ev.get("type") == "m.room.message":
                yield rid, ev["sender"], ev["content"].get("body", "")


def invite_from(r, sender):
    for rid, data in r.get("rooms", {}).get("invite", {}).items():
        for ev in data.get("invite_state", {}).get("events", []):
            if ev.get("type") == "m.room.member" and ev.get("sender") == sender:
                return rid


token = api("POST", "/_matrix/client/v3/login",
            {"type": "m.login.password", "identifier": {"type": "m.id.user", "user": USER},
             "password": PASSWORD})["access_token"]
sync()

control = api("POST", "/_matrix/client/v3/createRoom",
              {"preset": "trusted_private_chat", "is_direct": True, "invite": [BOT]})["room_id"]
wait_for(lambda r: any(s == BOT for _, s, _ in messages(r, control)), "heisenbridge to answer in its control room")
print("heisenbridge answered in the control room")

for cmd in ("ADDNETWORK bitlbee", "ADDSERVER bitlbee 127.0.0.1 6667", "OPEN bitlbee"):
    say(control, cmd)
network = wait_for(lambda r: invite_from(r, BOT), "the bitlbee network room invite")
api("POST", f"/_matrix/client/v3/join/{urllib.parse.quote(network)}", {})
print("joined the bitlbee network room")

say(network, "CONNECT")
hit = wait_for(lambda r: next((b for rid, s, b in messages(r) if "BitlBee" in b), None),
               "BitlBee's welcome over the bridge", timeout=90)
print("BitlBee answered over the bridge:", hit[:100])
PYEOF2
echo "BitlBee from Matrix check OK"

docker stop bitlbee-test && docker rm bitlbee-test

echo "=== Restricted-capability run (mirrors k8s/deployment.yaml securityContext) ==="
# k8s/deployment.yaml starts the container as root (s6-overlay needs this at
# startup) with capabilities dropped to just SETUID+SETGID (needed by
# s6-applyuidgid to drop each service to uid 1000). This run reproduces that
# exact profile so a regression here — e.g. a future s6-rc service needing a
# capability we don't grant — fails CI instead of only showing up at deploy
# time (see https://github.com/mbologna/docker-bitlbee/pull/88).
docker run -d --name bitlbee-test-restricted \
  --cap-drop=ALL --cap-add=SETUID --cap-add=SETGID \
  -e MATRIX_REGISTRATION_TOKEN=ci-test-token-restricted \
  "$IMAGE"

wait_healthy bitlbee-test-restricted

timeout 10s docker exec bitlbee-test-restricted nc -zv localhost 6697 || exit 1
echo "IRC TLS port 6697 OK under restricted capabilities"
timeout 10s docker exec bitlbee-test-restricted nc -zv localhost 6698 || exit 1
echo "IRC TLS port 6698 OK under restricted capabilities"
timeout 10s docker exec bitlbee-test-restricted nc -zv localhost 6699 || exit 1
echo "Matrix client TLS port 6699 OK under restricted capabilities"

docker stop bitlbee-test-restricted && docker rm bitlbee-test-restricted

