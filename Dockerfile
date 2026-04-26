# syntax=docker/dockerfile:1.23@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769

############################
# Builder stage
############################
FROM buildpack-deps:stable-scm@sha256:b9f67dbeca498aa5f4f7fc373e01a0541e629334a1b86a06e5ca524163dafd98 AS builder

LABEL org.opencontainers.image.title="BitlBee container" \
      org.opencontainers.image.description="A containerized version of BitlBee with additional plugins." \
      org.opencontainers.image.url="https://github.com/mbologna/docker-bitlbee" \
      org.opencontainers.image.licenses="MIT"

ARG BITLBEE_VERSION=3.6
# Check https://github.com/girlbossceo/conduwuit/releases for the latest version
ARG CONDUWUIT_VERSION=0.4.6
# Check https://github.com/mautrix/meta/releases for the latest version
ARG MAUTRIX_META_VERSION=0.2604.0
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /build

# Build dependencies - grouped by functionality for better caching
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    # Build tools
    autoconf automake build-essential cmake gcc git gperf libtool libtool-bin make pkg-config \
    # Protocol libraries
    libglib2.0-dev libhttp-parser-dev libotr5-dev libpurple-dev \
    libgnutls28-dev libjson-glib-dev libnss3-dev libssl-dev libgcrypt20-dev libgcrypt-dev \
    # Media libraries
    libpng-dev libwebp-dev libgdk-pixbuf-xlib-2.0-dev libopusfile-dev \
    librsvg2-bin imagemagick \
    # Additional dependencies
    libolm-dev libprotobuf-c-dev protobuf-c-compiler libqrencode-dev \
    libmarkdown2-dev libsqlite3-dev \
    # Utilities
    netcat-traditional curl ca-certificates golang gettext sudo

# Fetch all sources in parallel where possible
RUN --mount=type=cache,target=/root/.cache/go-build \
    curl -fsSL -o bitlbee.tar.gz https://get.bitlbee.org/src/bitlbee-${BITLBEE_VERSION}.tar.gz & \
    git clone --depth=1 --single-branch https://github.com/EionRobb/purple-discord.git & \
    git clone --depth=1 --single-branch https://github.com/matrix-org/purple-matrix.git & \
    git clone --depth=1 --single-branch https://github.com/EionRobb/purple-teams.git & \
    git clone --depth=1 --single-branch https://github.com/dylex/slack-libpurple.git & \
    git clone --depth=1 --single-branch https://github.com/BenWiederhake/tdlib-purple.git & \
    git clone --depth=1 --single-branch https://github.com/kensanata/bitlbee-mastodon.git & \
    git clone --depth=1 --single-branch --recurse-submodules --shallow-submodules \
      https://github.com/hoehermann/purple-gowhatsapp.git purple-whatsmeow & \
    wait

# Build BitlBee
RUN tar xf bitlbee.tar.gz
WORKDIR /build/bitlbee-${BITLBEE_VERSION}
RUN LDFLAGS="-lgcrypt" ./configure \
      --jabber=1 \
      --otr=1 \
      --purple=1 \
      --strip=1 \
      --ssl=gnutls \
      --systemdsystemunitdir=no && \
    make -j"$(nproc)" && \
    make install install-bin install-doc install-dev install-etc install-plugin-otr

# Download conduwuit (Matrix homeserver) and mautrix-meta (Facebook bridge) — statically linked, no extra deps
RUN case "${TARGETARCH}" in \
      amd64) CONDUWUIT_ARCH="x86_64"  ; MM_ARCH="amd64" ;; \
      arm64) CONDUWUIT_ARCH="aarch64" ; MM_ARCH="arm64"  ;; \
      *) echo "Unsupported arch: ${TARGETARCH}"; exit 1   ;; \
    esac && \
    curl -fsSL -o /usr/local/bin/conduwuit \
      "https://github.com/girlbossceo/conduwuit/releases/download/v${CONDUWUIT_VERSION}/static-${CONDUWUIT_ARCH}-unknown-linux-musl" && \
    chmod +x /usr/local/bin/conduwuit && \
    curl -fsSL -o /usr/local/bin/mautrix-meta \
      "https://github.com/mautrix/meta/releases/download/v${MAUTRIX_META_VERSION}/mautrix-meta-${MM_ARCH}" && \
    chmod +x /usr/local/bin/mautrix-meta

WORKDIR /build/purple-discord
RUN make -j"$(nproc)" && make install
WORKDIR /build/purple-matrix
RUN make -j"$(nproc)" && make install
WORKDIR /build/purple-teams
RUN make -j"$(nproc)" && make install

WORKDIR /build/slack-libpurple
RUN make install

WORKDIR /build/tdlib-purple
RUN ./build_and_install.sh

WORKDIR /build/bitlbee-mastodon
RUN ./autogen.sh && \
    ./configure && \
    make -j"$(nproc)" && \
    make install

WORKDIR /build
RUN cmake -S purple-whatsmeow -B whatsapp-build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build whatsapp-build && \
    cmake --install whatsapp-build --strip

RUN ldconfig && libtool --finish /usr/local/lib/bitlbee

############################
# Runtime stage
############################
FROM debian:stable-slim@sha256:8f0c555de6a2f9c2bda1b170b67479d11f7f5e3b66bb4a7a1d8843361c9dd3ff

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies with cache mount
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      libpurple0 libotr5 libssl3 libgnutls30 libgcrypt20 \
      libglib2.0-0 libjson-glib-1.0-0 libprotobuf-c1 \
      libhttp-parser2.9 libsqlite3-0 libopusfile0 \
      libwebp7 libolm3 libqrencode4 \
      libpng16-16 libgdk-pixbuf-2.0-0 \
      libstdc++6 zlib1g ca-certificates \
      # supervisor: manages conduwuit, mautrix-meta, bitlbee, and stunnel as sibling processes
      supervisor \
      # stunnel4 + openssl: TLS termination in front of BitlBee's loopback-only plaintext socket
      stunnel4 openssl \
      netcat-openbsd tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy binaries and libraries from builder
COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/sbin /usr/local/sbin
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /usr/local/share /usr/local/share
COPY --from=builder /usr/local/etc /usr/local/etc

# Copy purple plugins and their dependencies
COPY --from=builder /usr/lib/*-linux-gnu/purple-2 /tmp/purple-2/
COPY --from=builder /usr/share/pixmaps/pidgin /usr/share/pixmaps/pidgin/

# Install purple plugins to correct architecture directory
RUN ARCH_DIR=$(ls -d /usr/lib/*-linux-gnu 2>/dev/null | head -n1) && \
    mkdir -p "${ARCH_DIR}/purple-2" && \
    if [ -d /tmp/purple-2 ]; then \
      cp -a /tmp/purple-2/* "${ARCH_DIR}/purple-2/" && \
      rm -rf /tmp/purple-2; \
    fi && \
    # Run ldconfig to update library cache
    echo "/usr/local/lib" > /etc/ld.so.conf.d/usr-local.conf && \
    ldconfig && \
    # Verify plugins were copied
    ls -la "${ARCH_DIR}/purple-2/" || echo "Warning: No plugins found"

# Create bitlbee user and directories with proper permissions
RUN groupadd -r -g 1000 bitlbee && \
    useradd --system --uid 1000 --gid 1000 \
      --home-dir /var/lib/bitlbee \
      --shell /usr/sbin/nologin \
      --comment "BitlBee IRC Gateway" \
      bitlbee && \
    mkdir -p /var/lib/bitlbee /var/run && \
    chown -R bitlbee:bitlbee /var/lib/bitlbee && \
    touch /var/run/bitlbee.pid && \
    chown bitlbee:bitlbee /var/run/bitlbee.pid && \
    chmod 644 /var/run/bitlbee.pid

# Health check script — checks the TLS port only; plaintext is loopback-internal
COPY --chmod=755 <<'EOF' /usr/local/bin/healthcheck.sh
#!/bin/sh
nc -z localhost 6697 || exit 1
EOF

# supervisord config
# Processes start in priority order: conduwuit (10) → mautrix-meta (20) → bitlbee (30)
# All three auto-restart on failure; mautrix-meta retries many times since it waits for conduwuit
COPY --chmod=644 <<'EOF' /etc/supervisor/conf.d/bitlbee-stack.conf
[supervisord]
nodaemon=true
logfile=/var/lib/bitlbee/supervisord.log
logfile_maxbytes=5MB
pidfile=/var/lib/bitlbee/supervisord.pid

[program:conduwuit]
command=/usr/local/bin/conduwuit --config /var/lib/bitlbee/conduwuit/conduwuit.toml
priority=10
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:mautrix-meta]
command=/usr/local/bin/mautrix-meta --config /var/lib/bitlbee/mautrix-meta/config.yaml
priority=20
autostart=true
autorestart=true
startsecs=5
startretries=30
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:bitlbee]
command=/usr/local/sbin/bitlbee -F -n -v -i 127.0.0.1
priority=30
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:stunnel]
command=/usr/bin/stunnel4 /var/lib/bitlbee/stunnel.conf
priority=40
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

# Entrypoint: first-run init then supervisord
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

VOLUME ["/var/lib/bitlbee"]

USER bitlbee
WORKDIR /var/lib/bitlbee

EXPOSE 6697

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]
