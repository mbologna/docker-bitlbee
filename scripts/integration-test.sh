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
  -e UID=1000 -e GID=1000 \
  -e MATRIX_REGISTRATION_TOKEN=ci-test-token \
  "$IMAGE"

wait_healthy bitlbee-test

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

docker stop bitlbee-test-restricted && docker rm bitlbee-test-restricted

