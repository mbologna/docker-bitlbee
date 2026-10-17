#!/bin/bash
# entrypoint.sh — first-run initialization for tuwunel + mautrix-meta + bitlbee
#
# Installed as /etc/cont-init.d/10-init.sh; s6-overlay runs it before starting
# any services.  On first run this script generates:
#   1. A mautrix-meta appservice registration file (registration.yaml) with random tokens
#   2. A mautrix-meta config.yaml pointing to the local Matrix homeserver
#   3. A conduwuit.toml for the local Matrix homeserver (tuwunel)
#   4. Bootstraps tuwunel to register the mautrix-meta appservice in its database
#
# On subsequent runs it skips straight to exit 0 (s6 then starts the services).
#
# tuwunel is the successor of conduwuit, which this image shipped until 0.4.6.
# It reads conduwuit's config and migrates its database in place, so the paths
# below keep the conduwuit name, as upstream recommends.
#
# State lives in the persistent volume at /var/lib/bitlbee:
#   /var/lib/bitlbee/conduwuit/   — homeserver database + config
#   /var/lib/bitlbee/mautrix-meta/ — bridge database + config + registration

# s6-overlay runs cont-init scripts as root; drop to bitlbee for all file writes.
[ "$(id -u)" = "0" ] && exec s6-setuidgid bitlbee "$0" "$@"

set -euo pipefail

BITLBEE_DATA="/var/lib/bitlbee"
CONDUWUIT_DIR="${BITLBEE_DATA}/conduwuit"
MAUTRIX_DIR="${BITLBEE_DATA}/mautrix-meta"

mkdir -p "${CONDUWUIT_DIR}/db" "${MAUTRIX_DIR}"

# ── Step 1: mautrix-meta registration & config ────────────────────────────────
# The appservice registration file tells the homeserver which Matrix user namespace
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

    # Appservice registration — registered into the homeserver's database at startup (Step 4).
    # The regex defines which Matrix user IDs the bridge owns: the facebook_*
    # puppets and the bot itself. The homeserver only forwards events that match the
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

    # mautrix-meta config — connects the bridge to the local homeserver.
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
# have Step 4 register it again (the homeserver replaces a registration by id).
REREGISTER_APPSERVICE=0
if grep -q "regex: '@facebook_.+:localhost'" "${MAUTRIX_DIR}/registration.yaml"; then
    echo "[init] Adding the bridge bot to the appservice namespace..."
    sed -i "s/regex: '@facebook_.+:localhost'/regex: '@facebook(bot|_.+):localhost'/" \
        "${MAUTRIX_DIR}/registration.yaml"
    REREGISTER_APPSERVICE=1
fi

# ── Step 2: homeserver config ─────────────────────────────────────────────────
# tuwunel is a lightweight Matrix homeserver (conduwuit's successor, written in Rust).
# It runs on loopback only — no external Matrix federation, no TLS needed.
# allow_registration + registration_token means only people with the token can
# create accounts. Print the token clearly so the user can find it in the logs.
if [ ! -f "${CONDUWUIT_DIR}/conduwuit.toml" ]; then
    echo "[init] Generating homeserver config..."

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

log = "warn,tuwunel=info"
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
# 6697 → BitlBee, 6698 → matrix2051 (Matrix as an IRC network); both share the cert.
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
EOF

# matrix2051's RELEASE_TMP (see s6-rc.d/matrix2051/run)
mkdir -p "${BITLBEE_DATA}/matrix2051"

# ── Step 4: register mautrix-meta appservice with tuwunel ────────────────────
# The registration is kept in the homeserver's database (conduwuit had no config
# file option for this). We bootstrap it by starting tuwunel briefly, creating
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

    local reply
    reply=$(_admin_command "${base}" "${token}" "${room_id}" '!admin appservices list')
    if ! echo "${reply}" | grep -q '^Appservices'; then
        echo "[init] Unexpected reply to appservices list: ${reply}" >&2
        return 1
    fi
    if echo "${reply}" | grep -qw 'facebook-bridge'; then
        if [ "${REREGISTER_APPSERVICE}" = 0 ]; then
            echo "[init] Appservice already registered — skipping."
            return 0
        fi
        # The homeserver refuses to register an existing id: drop the old entry first.
        _admin_command "${base}" "${token}" "${room_id}" \
            '!admin appservices unregister facebook-bridge' > /dev/null
    fi

    # Register the appservice. The YAML goes in a code block below the command.
    reply=$(_admin_command "${base}" "${token}" "${room_id}" \
        "$(printf '!admin appservices register\n```\n%s\n```' "$(cat "${MAUTRIX_DIR}/registration.yaml")")")
    echo "[init] ${reply}"
    echo "${reply}" | grep -qi "registered" && return 0
    return 1
}

# Sends an admin command to the admin room and prints the server's reply,
# waiting up to 10s for it to arrive.
_admin_command() {
    local base="$1" token="$2" room_id="$3" body="$4"
    local txn="init$(date +%s%N)"
    curl -sf -X PUT "${base}/_matrix/client/v3/rooms/${room_id}/send/m.room.message/${txn}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        --data-binary "$(jq -n --arg body "${body}" '{"msgtype":"m.text","body":$body}')" \
        > /dev/null
    local i newest
    for i in $(seq 10); do
        sleep 1
        # The newest event is the reply once the server has answered our command.
        newest=$(curl -sf "${base}/_matrix/client/v3/rooms/${room_id}/messages?dir=b&limit=1" \
            -H "Authorization: Bearer ${token}")
        if [ "$(echo "${newest}" | jq -r '.chunk[0].sender')" = "@conduit:localhost" ]; then
            echo "${newest}" | jq -r '.chunk[0].content.body'
            return 0
        fi
    done
    return 1
}

# conduwuit -> tuwunel migration. The first tuwunel start converts a conduwuit
# database in place, and older images can't open it afterwards. Keep a copy
# first, and allow that start time to finish: killing tuwunel mid-migration could
# damage the database. The marker is written once tuwunel answers.
MIGRATION_MARKER="${CONDUWUIT_DIR}/.migrated-to-tuwunel"
MIGRATING=0
if [ ! -f "${MIGRATION_MARKER}" ] && [ -f "${CONDUWUIT_DIR}/db/CURRENT" ]; then
    MIGRATING=1
    BACKUP_DIR="${CONDUWUIT_DIR}/db.conduwuit-0.4.6-backup"
    echo "[init] Existing conduwuit database: migrating to tuwunel (one-way)."
    echo "[init] Keeping a copy in ${BACKUP_DIR}; delete it once everything works."
    rm -rf "${BACKUP_DIR}"
    cp -a "${CONDUWUIT_DIR}/db" "${BACKUP_DIR}"
fi

_tuwunel_register_appservice() {
    local base="http://127.0.0.1:6167"
    local start_timeout=30
    [ "${MIGRATING}" = 1 ] && start_timeout=600

    echo "[init] Starting tuwunel for appservice bootstrap..."
    /usr/local/bin/tuwunel --config "${CONDUWUIT_DIR}/conduwuit.toml" &
    local tuwunel_pid=$!

    # Wait for tuwunel to accept connections
    local i=0
    until curl -sf "${base}/_matrix/client/versions" > /dev/null 2>&1; do
        i=$((i + 1))
        if [ $i -ge "${start_timeout}" ] || ! kill -0 "$tuwunel_pid" 2>/dev/null; then
            echo "[init] ERROR: tuwunel did not start in time" >&2
            kill $tuwunel_pid 2>/dev/null || true
            return 1
        fi
        sleep 1
    done
    # Serving requests means the database is in tuwunel's format (migrated, or new).
    touch "${MIGRATION_MARKER}"

    # Capture the failure instead of letting set -e exit here: the temporary
    # tuwunel must be stopped either way, or it keeps the database lock and
    # the supervised tuwunel can't start.
    local bootstrap_exit=0
    _do_matrix_bootstrap "${base}" || bootstrap_exit=$?

    kill $tuwunel_pid 2>/dev/null || true
    # Give tuwunel a short grace period for WAL flush, then SIGKILL.
    # Graceful RocksDB shutdown can take 10+ minutes on constrained hardware
    # (full memtable flush + compaction). SIGKILL is safe here: the appservice
    # registration was already confirmed above, and RocksDB's WAL guarantees
    # data integrity on the next start.
    local deadline=$((SECONDS + 30))
    while kill -0 "$tuwunel_pid" 2>/dev/null && [ $SECONDS -lt $deadline ]; do
        sleep 1
    done
    kill -KILL "$tuwunel_pid" 2>/dev/null || true
    wait $tuwunel_pid 2>/dev/null || true
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

_tuwunel_register_appservice

# ── Step 5: hand off to s6-overlay ───────────────────────────────────────────
# s6-overlay will now start tuwunel → mautrix-meta → bitlbee → stunnel
# in dependency order and restart any process that crashes.
exit 0
