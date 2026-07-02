# syntax=docker/dockerfile:1.25@sha256:0adf442eae370b6087e08edc7c50b552d80ddf261576f4ebd6421006b2461f12

############################
# tdlib-builder stage (isolated so TDLib cache is not busted by unrelated version bumps)
############################
FROM --platform=$BUILDPLATFORM buildpack-deps:stable-scm@sha256:543f00635e939bb6edbcfa44d15238d8fdea7948bccffa63ae2833c5837a28b2 AS tdlib-builder

# tdlib-purple has no recent release tags; always build from master
ARG TDLIB_PURPLE_VERSION=master
ARG TARGETARCH
ARG BUILDPLATFORM

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /build

# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake git gperf gettext make pkg-config \
      libglib2.0-dev libpurple-dev libssl-dev zlib1g-dev ca-certificates \
      gcc-aarch64-linux-gnu g++-aarch64-linux-gnu

RUN git clone --depth=1 --single-branch --branch "${TDLIB_PURPLE_VERSION}" \
      --recurse-submodules --shallow-submodules \
      https://github.com/BenWiederhake/tdlib-purple.git

# Phase 1 — build TDLib code generators on the HOST arch (only needed for cross-compilation).
# prepare_cross_compiling requires DCMAKE_CROSSCOMPILING=True so cmake generates the target;
# without a toolchain file cmake still uses the host compiler, which is what we want here.
WORKDIR /build/tdlib-purple/td
COPY cmake/arm64.toolchain.cmake /arm64.toolchain.cmake
RUN if [ "${TARGETARCH}" = "arm64" ] && [ "${BUILDPLATFORM}" = "linux/amd64" ]; then \
      mkdir build-host && \
      cmake -S . -B build-host -DCMAKE_BUILD_TYPE=Release -DCMAKE_CROSSCOMPILING=True && \
      make -C build-host prepare_cross_compiling -j"$(nproc)"; \
    fi

# Phase 2 — build TDLib for TARGET arch (native or cross)
RUN if [ "${TARGETARCH}" = "arm64" ] && [ "${BUILDPLATFORM}" = "linux/amd64" ]; then \
      cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CROSSCOMPILING=True \
        -DCMAKE_TOOLCHAIN_FILE=/arm64.toolchain.cmake \
        -DTdNativeGeneratorsDir="$(pwd)/build-host"; \
    else \
      cmake -S . -B build -DCMAKE_BUILD_TYPE=Release; \
    fi && \
    make -C build -j"$(nproc)" && \
    make -C build install DESTDIR="$(pwd)/build/destdir"

# Phase 3 — build telegram-purple plugin against the TDLib we just built
WORKDIR /build/tdlib-purple
RUN if [ "${TARGETARCH}" = "arm64" ] && [ "${BUILDPLATFORM}" = "linux/amd64" ]; then \
      cmake -S . -B plugin-build \
        -DTd_DIR="$(pwd)/td/build/destdir/usr/local/lib/cmake/Td/" \
        -DNoVoip=True -DNoWebp=True \
        -DCMAKE_CROSSCOMPILING=True \
        -DCMAKE_TOOLCHAIN_FILE=/arm64.toolchain.cmake; \
    else \
      cmake -S . -B plugin-build \
        -DTd_DIR="$(pwd)/td/build/destdir/usr/local/lib/cmake/Td/" \
        -DNoVoip=True -DNoWebp=True; \
    fi && \
    make -C plugin-build -j"$(nproc)" && \
    make -C plugin-build install

############################
# Builder stage
############################
FROM --platform=$BUILDPLATFORM buildpack-deps:stable-scm@sha256:543f00635e939bb6edbcfa44d15238d8fdea7948bccffa63ae2833c5837a28b2 AS builder

LABEL org.opencontainers.image.title="BitlBee container" \
      org.opencontainers.image.description="A containerized version of BitlBee with additional plugins." \
      org.opencontainers.image.url="https://github.com/mbologna/docker-bitlbee" \
      org.opencontainers.image.licenses="MIT"

ARG BITLBEE_VERSION=3.6
# renovate: datasource=github-releases depName=just-containers/s6-overlay
ARG S6_OVERLAY_VERSION=3.2.3.0
# renovate: datasource=github-releases depName=girlbossceo/conduwuit
# Check https://github.com/girlbossceo/conduwuit/releases for the latest version
ARG CONDUWUIT_VERSION=0.4.6
# renovate: datasource=github-releases depName=mautrix/meta
# Check https://github.com/mautrix/meta/releases for the latest version
ARG MAUTRIX_META_VERSION=0.2606.0

# Plugin versions — tracked by Renovate where release tags are available.
# EionRobb plugins (discord, teams, googlechat) only publish nightly-HASH tags, not semver,
# so they stay on "master" (always latest) and Renovate does not track them.
# renovate: datasource=github-tags depName=EionRobb/purple-discord
ARG PURPLE_DISCORD_VERSION=master
# renovate: datasource=github-tags depName=EionRobb/purple-teams
ARG PURPLE_TEAMS_VERSION=master
# renovate: datasource=github-tags depName=EionRobb/purple-googlechat
ARG PURPLE_GOOGLECHAT_VERSION=master
# renovate: datasource=github-tags depName=kensanata/bitlbee-mastodon
ARG BITLBEE_MASTODON_VERSION=v1.4.5
# renovate: datasource=github-releases depName=hoehermann/purple-gowhatsapp
ARG PURPLE_WHATSMEOW_VERSION=v1.22.0

ARG TARGETARCH
ARG BUILDPLATFORM

ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /build

# Build dependencies - grouped by functionality for better caching
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    # Build tools
    autoconf automake build-essential cmake gcc git gperf libtool libtool-bin make pkg-config \
    # Protocol libraries
    libglib2.0-dev libotr5-dev libpurple-dev \
    libgnutls28-dev libjson-glib-dev libnss3-dev libssl-dev libgcrypt20-dev libgcrypt-dev \
    # Media libraries
    libpng-dev libwebp-dev libgdk-pixbuf-xlib-2.0-dev libopusfile-dev \
    librsvg2-bin imagemagick \
    # Additional dependencies
    libolm-dev libprotobuf-c-dev protobuf-c-compiler libqrencode-dev \
    libmarkdown2-dev libsqlite3-dev \
    # Cross-compilation toolchain (used when building for arm64 on amd64 runners)
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    # Utilities
    netcat-traditional curl ca-certificates golang gettext sudo

# Fetch all sources in parallel where possible
RUN --mount=type=cache,target=/root/.cache/go-build \
    curl -fsSL -o bitlbee.tar.gz https://get.bitlbee.org/src/bitlbee-${BITLBEE_VERSION}.tar.gz & \
    git clone --depth=1 --single-branch --branch ${PURPLE_DISCORD_VERSION} https://github.com/EionRobb/purple-discord.git & \
    git clone --depth=1 --single-branch --branch ${PURPLE_TEAMS_VERSION} https://github.com/EionRobb/purple-teams.git & \
    git clone --depth=1 --single-branch --branch ${PURPLE_GOOGLECHAT_VERSION} https://github.com/EionRobb/purple-googlechat.git & \
    git clone --depth=1 --single-branch --branch ${BITLBEE_MASTODON_VERSION} https://github.com/kensanata/bitlbee-mastodon.git & \
    git clone --depth=1 --single-branch --recurse-submodules --shallow-submodules \
      --branch ${PURPLE_WHATSMEOW_VERSION} https://github.com/hoehermann/purple-gowhatsapp.git purple-whatsmeow & \
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
WORKDIR /build/purple-teams
RUN make -j"$(nproc)" && make install
WORKDIR /build/purple-googlechat
RUN make -j"$(nproc)" && make install

# Copy TDLib libraries and telegram-purple plugin from the isolated builder stage
COPY --from=tdlib-builder /usr/local/lib/libTd* /usr/local/lib/
COPY --from=tdlib-builder /usr/lib/*-linux-gnu/purple-2 /tmp/tdlib-purple-2/
RUN ARCH_DIR=$(find /usr/lib -maxdepth 1 -type d -name '*-linux-gnu' | head -n1) && \
    mkdir -p "${ARCH_DIR}/purple-2" && \
    cp -a /tmp/tdlib-purple-2/. "${ARCH_DIR}/purple-2/" && \
    rm -rf /tmp/tdlib-purple-2

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

# Download and stage s6-overlay (noarch + arch-specific) into /s6-install.
# Extracted here in the builder so the runtime stage doesn't need xz-utils.
RUN case "${TARGETARCH}" in \
      amd64) S6_ARCH="x86_64"  ;; \
      arm64) S6_ARCH="aarch64" ;; \
      *) echo "Unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    mkdir /s6-install && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
      | tar -C /s6-install -Jxp && \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
      | tar -C /s6-install -Jxp

############################
# Runtime stage
############################
FROM debian:stable-slim@sha256:ee12ffb55625b99d62837a72f037d9b2f18fd0c787a89c2b9a4f09666c48776c

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies with cache mount
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      libpurple0 libotr5 libssl3 libgnutls30 libgcrypt20 \
      libglib2.0-0 libjson-glib-1.0-0 libprotobuf-c1 \
      libsqlite3-0 libopusfile0 \
      libwebp7 libolm3 libqrencode4 \
      libpng16-16 libgdk-pixbuf-2.0-0 \
      libstdc++6 zlib1g ca-certificates \
      # curl + jq: used by entrypoint bootstrap (Matrix API calls)
      curl jq \
      # stunnel4 + openssl: TLS termination in front of BitlBee's loopback-only plaintext socket
      stunnel4 openssl \
      netcat-openbsd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install s6-overlay from builder stage (avoids needing xz-utils in the runtime image)
COPY --from=builder /s6-install /

# Copy s6-rc.d service definitions; run scripts must be executable
COPY s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d
RUN chmod 755 /etc/s6-overlay/s6-rc.d/*/run

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
RUN ARCH_DIR=$(find /usr/lib -maxdepth 1 -type d -name '*-linux-gnu' | head -n1) && \
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

# Entrypoint: first-run init script, run by s6-overlay before services start
COPY --chmod=755 entrypoint.sh /etc/cont-init.d/10-init.sh

VOLUME ["/var/lib/bitlbee"]

WORKDIR /var/lib/bitlbee

EXPOSE 6697

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD ["/usr/local/bin/healthcheck.sh"]

# s6-overlay is PID 1 — handles init, zombie reaping, and service supervision
ENTRYPOINT ["/init"]
