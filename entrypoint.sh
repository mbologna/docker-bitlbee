#!/bin/bash
# entrypoint.sh — first-run initialization for conduwuit + mautrix-meta + bitlbee
#
# Installed as /etc/cont-init.d/10-init.sh; s6-overlay runs it before starting
# any services.  On first run this script generates:
#   1. A mautrix-meta appservice registration file (registration.yaml) with random tokens
#   2. A mautrix-meta config.yaml pointing to the local conduwuit homeserver
#   3. A conduwuit.toml for the local Matrix homeserver
#   4. Bootstraps conduwuit to register the mautrix-meta appservice in its database
#
# On subsequent runs it skips straight to exit 0 (s6 then starts the services).
#
# State lives in the persistent volume at /var/lib/bitlbee:
#   /var/lib/bitlbee/conduwuit/   — conduwuit database + config
#   /var/lib/bitlbee/mautrix-meta/ — bridge database + config + registration

# s6-overlay runs cont-init scripts as root; drop to bitlbee for all file writes.
[ "$(id -u)" = "0" ] && exec s6-setuidgid bitlbee "$0" "$@"

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

    # Generate 64-char hex tokens without openssl (coreutils only).
    # pipefail must be off here: tr gets SIGPIPE (exit 141) when head exits,
    # which would abort the script under set -euo pipefail.
    set +o pipefail
    AS_TOKEN=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 64)
    HS_TOKEN=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 64)
    set -o pipefail

    # Appservice registration — registered into conduwuit's database at startup (Step 4).
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

    # Allow overriding the registration token via environment variable.
    # pipefail off for the same SIGPIPE reason as the token generation above.
    set +o pipefail
    REG_TOKEN="${MATRIX_REGISTRATION_TOKEN:-$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32)}"
    set -o pipefail

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

# ── Step 3: TLS certificate + stunnel config ─────────────────────────────────
# BitlBee is forced to loopback (127.0.0.1) so it is never reachable on
# plaintext from outside the container. stunnel terminates TLS on 6697 and
# forwards to 127.0.0.1:6667. The self-signed cert lives in the persistent
# volume so it survives container restarts.
SSL_DIR="${BITLBEE_DATA}/ssl"
if [ ! -f "${SSL_DIR}/bitlbee.pem" ]; then
    echo "[init] Generating self-signed TLS certificate..."
    mkdir -p "${SSL_DIR}"
    openssl req -x509 -newkey rsa:4096 \
        -keyout "${SSL_DIR}/key.pem" \
        -out "${SSL_DIR}/cert.pem" \
        -days 3650 -nodes \
        -subj "/CN=bitlbee" 2>/dev/null
    # stunnel expects cert and key concatenated in a single PEM file
    cat "${SSL_DIR}/cert.pem" "${SSL_DIR}/key.pem" > "${SSL_DIR}/bitlbee.pem"
    rm "${SSL_DIR}/cert.pem" "${SSL_DIR}/key.pem"
    chmod 600 "${SSL_DIR}/bitlbee.pem"
    echo "[init] TLS certificate written to ${SSL_DIR}/bitlbee.pem"
fi

# Always (re-)write stunnel.conf so the path is correct even after volume moves.
cat > "${BITLBEE_DATA}/stunnel.conf" <<EOF
foreground = yes
syslog = no

[bitlbee-tls]
accept = 6697
connect = 127.0.0.1:6667
cert = ${SSL_DIR}/bitlbee.pem
EOF

# ── Step 4: register mautrix-meta appservice with conduwuit ──────────────────
# conduwuit stores appservice registrations in its database — there is no config
# file option for this. We bootstrap it by starting conduwuit briefly, creating
# an internal admin account, and sending the !admin appservices register command
# to the admin room via the Matrix API. The admin account is only used for this
# purpose and is never exposed externally.
#
# This step is idempotent: it checks whether the appservice is already registered
# before attempting to register it, so it is safe to run on every container start.
ADMIN_USER="conduwuit-init"
ADMIN_PASS="$(cat "${CONDUWUIT_DIR}/init_admin_pass" 2>/dev/null || true)"

_do_matrix_bootstrap() {
    local base="$1"
    local reg_token="$2"

    # Register admin account (idempotent — ok if already exists)
    local session
    session=$(curl -sf -X POST "${base}/_matrix/client/v3/register" \
        -H "Content-Type: application/json" -d '{}' | jq -r '.session // empty') || true
    curl -sf -X POST "${base}/_matrix/client/v3/register" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\",\"auth\":{\"type\":\"m.login.registration_token\",\"token\":\"${reg_token}\",\"session\":\"${session}\"}}" \
        > /dev/null 2>&1 || true

    # Login
    local token
    token=$(curl -sf -X POST "${base}/_matrix/client/v3/login" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"${ADMIN_USER}\"},\"password\":\"${ADMIN_PASS}\"}" \
        | jq -r '.access_token')
    [ -z "$token" ] && { echo "[init] Login failed" >&2; return 1; }

    # Get admin room
    local room_id
    room_id=$(curl -sf "${base}/_matrix/client/v3/joined_rooms" \
        -H "Authorization: Bearer ${token}" | jq -r '.joined_rooms[0]')
    [ -z "$room_id" ] && { echo "[init] No admin room found" >&2; return 1; }

    # Check if appservice is already registered
    local txn
    txn=$(date +%s%N)
    curl -sf -X PUT "${base}/_matrix/client/v3/rooms/${room_id}/send/m.room.message/${txn}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d '{"msgtype":"m.text","body":"!admin appservices list-registered"}' > /dev/null
    sleep 1
    local msgs
    msgs=$(curl -sf "${base}/_matrix/client/v3/rooms/${room_id}/messages?dir=b&limit=3" \
        -H "Authorization: Bearer ${token}")
    if echo "$msgs" | jq -r '.chunk[].content.body' 2>/dev/null | grep -q "facebook-bridge"; then
        echo "[init] Appservice already registered — skipping."
        return 0
    fi

    # Register the appservice
    local yaml_content
    yaml_content=$(cat "${MAUTRIX_DIR}/registration.yaml")
    # Build the message body carefully to preserve newlines in the YAML block
    local msg_body
    msg_body=$(printf '!admin appservices register\n```\n%s\n```' "${yaml_content}")
    txn=$(( txn + 1 ))
    curl -sf -X PUT "${base}/_matrix/client/v3/rooms/${room_id}/send/m.room.message/${txn}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        --data-binary "$(jq -n --arg body "${msg_body}" '{"msgtype":"m.text","body":$body}')" \
        > /dev/null
    sleep 2

    # Confirm registration
    msgs=$(curl -sf "${base}/_matrix/client/v3/rooms/${room_id}/messages?dir=b&limit=3" \
        -H "Authorization: Bearer ${token}")
    local result
    result=$(echo "$msgs" | jq -r '.chunk[] | select(.sender == "@conduit:localhost") | .content.body' | head -1)
    echo "[init] ${result}"
    echo "$result" | grep -qi "registered" && return 0
    return 1
}

_conduwuit_register_appservice() {
    local base="http://127.0.0.1:6167"
    local reg_token
    reg_token=$(grep 'registration_token' "${CONDUWUIT_DIR}/conduwuit.toml" | sed 's/.*= *"\(.*\)"/\1/')

    echo "[init] Starting conduwuit for appservice bootstrap..."
    /usr/local/bin/conduwuit --config "${CONDUWUIT_DIR}/conduwuit.toml" &
    local conduwuit_pid=$!

    # Wait for conduwuit to accept connections (up to 30s)
    local i=0
    until curl -sf "${base}/_matrix/client/versions" > /dev/null 2>&1; do
        i=$((i + 1))
        if [ $i -ge 30 ]; then
            echo "[init] ERROR: conduwuit did not start in time" >&2
            kill $conduwuit_pid 2>/dev/null || true
            return 1
        fi
        sleep 1
    done

    _do_matrix_bootstrap "${base}" "${reg_token}"
    local bootstrap_exit=$?

    kill $conduwuit_pid 2>/dev/null || true
    # Give conduwuit a short grace period for WAL flush, then SIGKILL.
    # Graceful RocksDB shutdown can take 10+ minutes on constrained hardware
    # (full memtable flush + compaction). SIGKILL is safe here: the appservice
    # registration was already confirmed above, and RocksDB's WAL guarantees
    # data integrity on the next start.
    local deadline=$((SECONDS + 30))
    while kill -0 "$conduwuit_pid" 2>/dev/null && [ $SECONDS -lt $deadline ]; do
        sleep 1
    done
    kill -KILL "$conduwuit_pid" 2>/dev/null || true
    wait $conduwuit_pid 2>/dev/null || true
    return $bootstrap_exit
}

# Generate and persist the init admin password on first run
if [ -z "${ADMIN_PASS}" ]; then
    set +o pipefail
    ADMIN_PASS=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32)
    set -o pipefail
    echo "${ADMIN_PASS}" > "${CONDUWUIT_DIR}/init_admin_pass"
    chmod 600 "${CONDUWUIT_DIR}/init_admin_pass"
fi

_conduwuit_register_appservice

# ── Step 5: hand off to s6-overlay ───────────────────────────────────────────
# s6-overlay will now start conduwuit → mautrix-meta → bitlbee → stunnel
# in dependency order and restart any process that crashes.
exit 0
