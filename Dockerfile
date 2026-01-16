# syntax=docker/dockerfile:1.7

############################
# Builder stage
############################
FROM buildpack-deps:stable-scm AS builder

LABEL org.opencontainers.image.title="BitlBee container" \
      org.opencontainers.image.description="A containerized version of BitlBee with additional plugins." \
      org.opencontainers.image.url="https://github.com/mbologna/docker-bitlbee" \
      org.opencontainers.image.licenses="MIT"

ARG BITLBEE_VERSION=3.6
ARG FACEBOOK_VERSION=1.2.2
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    LDFLAGS="-lgcrypt" \
    MAKEFLAGS="-j$(nproc)"

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
    libgnutls28-dev libjson-glib-dev libnss3-dev libssl-dev libgcrypt20-dev \
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
    curl -fsSL -o facebook.tar.gz https://github.com/bitlbee/bitlbee-facebook/archive/v${FACEBOOK_VERSION}.tar.gz & \
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
RUN ./configure --jabber=1 --otr=1 --purple=1 --strip=1 --ssl=gnutls --systemdsystemunitdir=no && \
    make -j"$(nproc)" && \
    make install install-bin install-doc install-dev install-etc install-plugin-otr

WORKDIR /build/purple-discord
RUN make && make install

WORKDIR /build/purple-matrix
RUN make && make install

WORKDIR /build/purple-teams
RUN make && make install

WORKDIR /build/slack-libpurple
RUN make install

WORKDIR /build
RUN tar xf facebook.tar.gz
WORKDIR /build/bitlbee-facebook-${FACEBOOK_VERSION}
RUN ./autogen.sh && make && make install

WORKDIR /build/bitlbee-mastodon
RUN ./autogen.sh && ./configure && make -j"$(nproc)" && make install

WORKDIR /build
RUN cmake -S purple-whatsmeow -B whatsapp-build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build whatsapp-build && \
    cmake --install whatsapp-build --strip

RUN ldconfig && libtool --finish /usr/local/lib/bitlbee

############################
# Runtime stage
############################
FROM debian:stable-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies with cache mount
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      libpurple0 libotr5 libssl3 libgnutls30 libgcrypt20 \
      libglib2.0-0 libjson-glib-1.0-0 libprotobuf-c1 \
      libhttp-parser2.9 libsqlite3-0 ca-certificates \
      netcat-openbsd tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy binaries and libraries from builder
COPY --from=builder /usr/local /usr/local
COPY --from=builder /usr/lib/*-linux-gnu/purple-2 /usr/lib/purple-2-temp/

# Install purple plugins to correct architecture directory
RUN ARCH_DIR=$(find /usr/lib -maxdepth 1 -name "*-linux-gnu" | head -n1) && \
    mkdir -p "${ARCH_DIR}/purple-2" && \
    cp -r /usr/lib/purple-2-temp/* "${ARCH_DIR}/purple-2/" && \
    rm -rf /usr/lib/purple-2-temp && \
    ldconfig

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

# Health check script
COPY --chmod=755 <<'EOF' /usr/local/bin/healthcheck.sh
#!/bin/sh
nc -z localhost 6667 || exit 1
EOF

VOLUME ["/var/lib/bitlbee"]

USER bitlbee
WORKDIR /var/lib/bitlbee

EXPOSE 6667

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/sbin/bitlbee", "-F", "-n", "-v"]
