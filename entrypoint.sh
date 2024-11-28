#!/bin/bash
set -euxo pipefail
# Debug log for ownership check
echo "Current owner of /var/lib/bitlbee: $(stat -c %U /var/lib/bitlbee)"

if [ "$(stat -c %U /var/lib/bitlbee)" != "bitlbee" ]; then
    echo "Changing ownership of /var/lib/bitlbee to bitlbee"
    chown -R bitlbee:nogroup /var/lib/bitlbee || echo "Failed to change ownership"
else
    echo "Ownership is already correct"
fi
exec "$@"
