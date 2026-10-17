#!/bin/bash
# entrypoint.sh — first-run initialization for conduwuit + mautrix-meta + heisenbridge + bitlbee
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
HEISENBRIDGE_DIR="${BITLBEE_DATA}/heisenbridge"

mkdir -p "${CONDUWUIT_DIR}/db" "${MAUTRIX_DIR}" "${HEISENBRIDGE_DIR}"

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
    # The regex defines which Matrix user IDs the bridge owns: the facebook_*
    # puppets and the bot itself. conduwuit only forwards events that match the
    # namespace, so without the bot in it, invites to the bot never arrive.
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
      regex: '@facebook(bot|_.+):localhost'
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

# Registrations written before the bot was in the namespace: fix the file and
# have Step 4 register it again (conduwuit replaces a registration by id).
REREGISTER_APPSERVICE=0
if grep -q "regex: '@facebook_.+:localhost'" "${MAUTRIX_DIR}/registration.yaml"; then
    echo "[init] Adding the bridge bot to the appservice namespace..."
    sed -i "s/regex: '@facebook_.+:localhost'/regex: '@facebook(bot|_.+):localhost'/" \
        "${MAUTRIX_DIR}/registration.yaml"
    REREGISTER_APPSERVICE=1
fi

# ── Step 1b: heisenbridge registration ───────────────────────────────────────
# Heisenbridge bridges BitlBee into Matrix: a Matrix client sees each BitlBee
# contact as a direct chat. It keeps its own state in the homeserver, so the
# registration file is all it needs. Same shape as `heisenbridge
# --generate-compat`: the bot is in the namespace, which conduwuit requires.
if [ ! -f "${HEISENBRIDGE_DIR}/registration.yaml" ]; then
    echo "[init] Generating heisenbridge registration tokens..."
    set +o pipefail
    HB_AS_TOKEN=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 64)
    HB_HS_TOKEN=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 64)
    set -o pipefail
    cat > "${HEISENBRIDGE_DIR}/registration.yaml" <<EOF
id: heisenbridge
url: http://127.0.0.1:9898
as_token: ${HB_AS_TOKEN}
hs_token: ${HB_HS_TOKEN}
sender_localpart: heisenbridge
rate_limited: false
namespaces:
  users:
    - exclusive: true
      regex: '@irc_.*'
    - exclusive: true
      regex: '@heisenbridge:.*'
  aliases: []
  rooms: []
EOF
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
    echo "║  Create your Matrix account with:                            ║"
    echo "║    docker exec <container> matrix-register <user> <password> ║"
    echo "║  then connect your IRC client to port 6698 (see README)      ║"
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
# 6697 → BitlBee, 6698 → matrix2051 (Matrix as an IRC network), 6699 → conduwuit's
# client API (for Matrix clients such as Element); all share the cert.
cat > "${BITLBEE_DATA}/stunnel.conf" <<EOF
foreground = yes
syslog = no

[bitlbee-tls]
accept = 6697
connect = 127.0.0.1:6667
cert = ${SSL_DIR}/bitlbee.pem

[matrix2051-tls]
accept = 6698
connect = 127.0.0.1:2051
cert = ${SSL_DIR}/bitlbee.pem

[matrix-client-tls]
accept = 6699
connect = 127.0.0.1:6167
cert = ${SSL_DIR}/bitlbee.pem
EOF

# matrix2051's RELEASE_TMP (see s6-rc.d/matrix2051/run)
mkdir -p "${BITLBEE_DATA}/matrix2051"

# ── Step 4: register the appservices with conduwuit ──────────────────────────
# conduwuit stores appservice registrations in its database — there is no config
# file option for this. We bootstrap it by starting conduwuit briefly, creating
# an internal admin account, and sending the !admin appservices register command
# to the admin room via the Matrix API. The admin account is only used for this
# purpose and is never exposed externally.
#
# This step is idempotent: it checks whether each appservice is already
# registered before registering it, so it is safe to run on every container start.
ADMIN_USER="conduwuit-init"
ADMIN_PASS="$(cat "${CONDUWUIT_DIR}/init_admin_pass" 2>/dev/null || true)"

_do_matrix_bootstrap() {
    local base="$1"

    # Register admin account (idempotent — ok if already exists)
    /usr/local/bin/matrix-register --no-bridge-room "${ADMIN_USER}" "${ADMIN_PASS}" "${base}" \
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

    # Each entry: <appservice id> <registration file> <force re-register 0/1>
    local rc=0
    _register_appservice "$base" "$token" "$room_id" facebook-bridge \
        "${MAUTRIX_DIR}/registration.yaml" "${REREGISTER_APPSERVICE}" || rc=1
    _register_appservice "$base" "$token" "$room_id" heisenbridge \
        "${HEISENBRIDGE_DIR}/registration.yaml" 0 || rc=1
    return $rc
}

# Sends "!admin appservices register" with a registration file to the admin
# room, unless that id is already registered (and no re-registration is forced).
_register_appservice() {
    local base="$1" token="$2" room_id="$3" as_id="$4" yaml_file="$5" force="$6"
    local txn msgs
    txn=$(date +%s%N)
    curl -sf -X PUT "${base}/_matrix/client/v3/rooms/${room_id}/send/m.room.message/${txn}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d '{"msgtype":"m.text","body":"!admin appservices list-registered"}' > /dev/null
    sleep 1
    msgs=$(curl -sf "${base}/_matrix/client/v3/rooms/${room_id}/messages?dir=b&limit=3" \
        -H "Authorization: Bearer ${token}")
    if [ "${force}" = 0 ] &&
        echo "$msgs" | jq -r '.chunk[] | select(.sender == "@conduit:localhost") | .content.body' \
            2>/dev/null | head -1 | grep -qw "${as_id}"; then
        echo "[init] Appservice ${as_id} already registered — skipping."
        return 0
    fi

    # Build the message body carefully to preserve newlines in the YAML block
    local msg_body
    msg_body=$(printf '!admin appservices register\n```\n%s\n```' "$(cat "${yaml_file}")")
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

    # Capture the failure instead of letting set -e exit here: the temporary
    # conduwuit must be stopped either way, or it keeps the database lock and
    # the supervised conduwuit can't start.
    local bootstrap_exit=0
    _do_matrix_bootstrap "${base}" || bootstrap_exit=$?

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
