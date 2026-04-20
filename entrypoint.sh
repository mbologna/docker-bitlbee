#!/bin/bash
# entrypoint.sh — first-run initialization for conduwuit + mautrix-meta + bitlbee
#
# On first run this script generates:
#   1. A mautrix-meta appservice registration file (registration.yaml) with random tokens
#   2. A mautrix-meta config.yaml pointing to the local conduwuit homeserver
#   3. A conduwuit.toml referencing the registration file above
#
# On subsequent runs it skips straight to supervisord.
#
# State lives in the persistent volume at /var/lib/bitlbee:
#   /var/lib/bitlbee/conduwuit/   — conduwuit database + config
#   /var/lib/bitlbee/mautrix-meta/ — bridge database + config + registration

set -euo pipefail

BITLBEE_DATA="/var/lib/bitlbee"
CONDUWUIT_DIR="${BITLBEE_DATA}/conduwuit"
MAUTRIX_DIR="${BITLBEE_DATA}/mautrix-meta"

mkdir -p "${CONDUWUIT_DIR}/db" "${MAUTRIX_DIR}"

# ── Step 1: mautrix-meta registration & config ────────────────────────────────
# The appservice registration file tells conduwuit which Matrix user namespace
# the bridge owns and which shared secret tokens to use for auth.
# We generate it once; rotating tokens later requires restarting both services.
if [ ! -f "${MAUTRIX_DIR}/registration.yaml" ]; then
    echo "[init] First run detected — generating mautrix-meta registration tokens..."

    # Generate 64-char hex tokens without openssl (coreutils only)
    AS_TOKEN=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 64)
    HS_TOKEN=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 64)

    # Appservice registration — read by conduwuit at startup.
    # The regex defines which Matrix user IDs the bridge is allowed to create
    # (facebook_* users on this homeserver).
    cat > "${MAUTRIX_DIR}/registration.yaml" <<EOF
id: facebook-bridge
url: http://127.0.0.1:29319
as_token: ${AS_TOKEN}
hs_token: ${HS_TOKEN}
sender_localpart: facebookbot
rate_limited: false
namespaces:
  users:
    - exclusive: true
      regex: '@facebook_.+:localhost'
  aliases: []
  rooms: []
de.sorunome.msc2409.push_ephemeral: true
receive_ephemeral: true
EOF

    # mautrix-meta config — connects the bridge to the local conduwuit instance.
    # bridge.permissions controls who may use the bridge:
    #   '*': relay   → anyone can receive messages but can't log in
    #   'localhost': user → accounts on this server can link their Facebook account
    # To restrict to specific Matrix users, replace 'localhost' with '@you:localhost': admin
    cat > "${MAUTRIX_DIR}/config.yaml" <<EOF
homeserver:
    address: http://127.0.0.1:6167
    domain: localhost
    software: standard
    status_endpoint: null
    message_send_checkpoint_endpoint: null
    async_media: false
    websocket: false
    ping_interval_seconds: 0

appservice:
    address: http://127.0.0.1:29319
    hostname: 127.0.0.1
    port: 29319
    id: facebook-bridge
    bot:
        username: facebookbot
        displayname: Facebook Bridge Bot
        avatar: mxc://maunium.net/ygtkteZsXnGJLJHRchUwYWak
    as_token: ${AS_TOKEN}
    hs_token: ${HS_TOKEN}

meta:
    # 'facebook' for Messenger, 'instagram' for Instagram DMs
    mode: facebook

bridge:
    username_template: facebook_{{.}}
    displayname_template: '{{or .PushName .FullName | trim}} (Facebook)'
    private_chat_portal_meta: default
    portal_message_buffer: 128
    user_avatar_sync: true
    bridge_matrix_leave: true
    sync_with_custom_puppets: false
    sync_direct_chat_list: false
    double_puppet_allow_discovery: false
    login_shared_secret_map: {}
    encryption:
        allow: false
        default: false
    permissions:
        '*': relay
        'localhost': user
    relay:
        enabled: false

matrix:
    federate_rooms: false

database:
    type: sqlite3-fk-wal
    uri: file:${MAUTRIX_DIR}/mautrix-meta.db?_txlock=immediate

logging:
    min_level: info
    writers:
        - type: stdout
          format: pretty-colored
          time_format: " "
          part_format: "{level}: {msg}\n"
EOF

    echo "[init] mautrix-meta config written to ${MAUTRIX_DIR}/config.yaml"
fi

# ── Step 2: conduwuit config ──────────────────────────────────────────────────
# conduwuit is a lightweight Matrix homeserver (fork of Conduit, written in Rust).
# It runs on loopback only — no external Matrix federation, no TLS needed.
# allow_registration + registration_token means only people with the token can
# create accounts. Print the token clearly so the user can find it in the logs.
if [ ! -f "${CONDUWUIT_DIR}/conduwuit.toml" ]; then
    echo "[init] Generating conduwuit config..."

    # Allow overriding the registration token via environment variable
    REG_TOKEN="${MATRIX_REGISTRATION_TOKEN:-$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32)}"

    cat > "${CONDUWUIT_DIR}/conduwuit.toml" <<EOF
[global]
# The Matrix server name embedded in all user IDs: @user:localhost
# Changing this after first run will break existing accounts.
server_name = "localhost"

database_backend = "rocksdb"
database_path = "${CONDUWUIT_DIR}/db"

# Loopback only — BitlBee and mautrix-meta connect from inside the container
address = "127.0.0.1"
port = 6167

# No federation: this is a private, single-container homeserver
allow_federation = false

# Registration requires a token so random users on the internet can't sign up
allow_registration = true
registration_token = "${REG_TOKEN}"

log = "warn,conduwuit=info"
EOF

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         Matrix homeserver first-run setup complete           ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  Matrix registration token: ${REG_TOKEN}"
    echo "║                                                              ║"
    echo "║  You need this to create your Matrix account in BitlBee:    ║"
    echo "║    register --token=${REG_TOKEN} \\   ║"
    echo "║             username password                                ║"
    echo "║  (see README for full setup steps)                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
fi

# ── Step 3: hand off to supervisord ──────────────────────────────────────────
# supervisord starts conduwuit → mautrix-meta → bitlbee in priority order
# and restarts any process that crashes.
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/bitlbee-stack.conf
