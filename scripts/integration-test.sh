#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE_REF:-${DOCKER_USERNAME}/docker-bitlbee:latest}"

docker pull "$IMAGE"

docker run -d --name bitlbee-test \
  -e UID=1000 -e GID=1000 \
  -e MATRIX_REGISTRATION_TOKEN=ci-test-token \
  "$IMAGE"

for i in {1..45}; do
  STATUS=$(docker inspect --format="{{.State.Health.Status}}" bitlbee-test 2>/dev/null || echo "gone")
  RUNNING=$(docker inspect --format="{{.State.Running}}" bitlbee-test 2>/dev/null || echo "false")
  if [ "$RUNNING" != "true" ]; then
    echo "Container stopped unexpectedly"
    docker logs bitlbee-test
    docker rm bitlbee-test || true
    exit 1
  fi
  if [ "$STATUS" = "healthy" ]; then
    echo "Container is healthy"
    break
  fi
  echo "Waiting... ($i/45) [status=$STATUS]"
  sleep 2
done

if [ "$STATUS" != "healthy" ]; then
  echo "Container failed to become healthy"
  docker logs bitlbee-test
  docker rm bitlbee-test || true
  exit 1
fi

timeout 10s docker exec bitlbee-test nc -zv localhost 6697 || exit 1
echo "IRC TLS port 6697 OK"

docker stop bitlbee-test && docker rm bitlbee-test

