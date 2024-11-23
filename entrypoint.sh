#!/bin/bash
set -euxo pipefail
# Ensure proper permissions on the mounted data directory
if [ "$(stat -c %U /var/lib/bitlbee)" != "bitlbee" ]; then
    chown -R bitlbee:nogroup /var/lib/bitlbee
fi
exec "$@"
