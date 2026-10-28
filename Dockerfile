# syntax=docker/dockerfile:1.28@sha256:bb22d9815c728170f72750f4e5b0d672e06176142e1d602c7e66c050100b7e5b

############################
# Component versions
############################
# Global so the runtime stage can label the image with them. Each stage that
# uses one redeclares it (bare ARG), so tdlib-builder's cache still only
# depends on TDLIB_PURPLE_VERSION.
#
# The image's own version (git tag vX.Y.Z) is independent of all of these:
# see "Versioning" in README.md.

# Components with no usable release tags are built from a branch, pinned to a
# full commit SHA. An unpinned branch HEAD would reach the weekly release
# unreviewed, and infra deploys this image. Renovate (git-refs) proposes the
# branch's new HEAD as a digest update; the comment's currentValue names the
# branch it follows. git-refs gives no commit dates, so no release-age gate
# applies: the digest PR automerges once CI builds and tests the image.
# renovate: datasource=git-refs depName=BenWiederhake/tdlib-purple packageName=https://github.com/BenWiederhake/tdlib-purple currentValue=master
ARG TDLIB_PURPLE_VERSION=43e6cc2f14ccd08171b1515f6216f4bbf84eed80
ARG BITLBEE_VERSION=3.6
# renovate: datasource=github-releases depName=just-containers/s6-overlay
ARG S6_OVERLAY_VERSION=3.2.3.0
# Matrix homeserver. tuwunel is the successor of conduwuit (archived at 0.4.6) and
# migrates a conduwuit database in place on first start (one-way).
# renovate: datasource=github-releases depName=matrix-construct/tuwunel
ARG TUWUNEL_VERSION=1.9.4
# renovate: datasource=github-releases depName=mautrix/meta
# Check https://github.com/mautrix/meta/releases for the latest version
ARG MAUTRIX_META_VERSION=0.2609.0
# matrix2051 (Matrix client exposed as an IRC server) has no release tags;
# built from main, pinned as above
# renovate: datasource=git-refs depName=progval/matrix2051 packageName=https://github.com/progval/matrix2051 currentValue=main
ARG MATRIX2051_VERSION=ef7f1ea7f6a036b0cb34f36fd41d4bdde5d71a7b

# Plugin versions — tracked by Renovate where release tags are available.
# EionRobb plugins (discord, teams, googlechat) only publish nightly-HASH tags, not semver,
# so they are built from master, pinned to a commit SHA as above.
# renovate: datasource=git-refs depName=EionRobb/purple-discord packageName=https://github.com/EionRobb/purple-discord currentValue=master
ARG PURPLE_DISCORD_VERSION=ef5993d5677978c08df845601b385f42a23132a9
# renovate: datasource=git-refs depName=EionRobb/purple-teams packageName=https://github.com/EionRobb/purple-teams currentValue=master
ARG PURPLE_TEAMS_VERSION=07795b6ab57a1db7dc1fb00d956d558a18da0988
# renovate: datasource=git-refs depName=EionRobb/purple-googlechat packageName=https://github.com/EionRobb/purple-googlechat currentValue=master
ARG PURPLE_GOOGLECHAT_VERSION=fbd99caead1220900bc439957a4c5638ae143005
# renovate: datasource=github-tags depName=kensanata/bitlbee-mastodon
ARG BITLBEE_MASTODON_VERSION=v1.4.5
# renovate: datasource=github-releases depName=hoehermann/purple-gowhatsapp
ARG PURPLE_WHATSMEOW_VERSION=v1.26.0
# purple-whatsmeow builds against whatsmeow "latest", whose Blocklist API has since
# changed. Pin the library to the version v1.26.0 was released with (its committed
# go.mod). Bump together with PURPLE_WHATSMEOW_VERSION.
ARG WHATSMEOW_VERSION=v0.0.0-20260909164725-b25a56d63729

############################
# tdlib-builder stage (isolated so TDLib cache is not busted by unrelated version bumps)
############################
FROM --platform=$BUILDPLATFORM buildpack-deps:stable-scm@sha256:494c8cd78eee342bcab52bf7d31d77755aaa770f5d8e668685def8f7b8d34d77 AS tdlib-builder

ARG TDLIB_PURPLE_VERSION
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

# Fetch the pinned commit by SHA (git clone --branch takes no SHA)
RUN git init -q tdlib-purple && \
    git -C tdlib-purple fetch -q --depth=1 \
      https://github.com/BenWiederhake/tdlib-purple.git "${TDLIB_PURPLE_VERSION}" && \
    git -C tdlib-purple -c advice.detachedHead=false checkout -q FETCH_HEAD && \
    git -C tdlib-purple submodule update -q --init --recursive --depth=1

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
# matrix2051-builder stage
############################
# Built for the TARGET platform (no --platform=$BUILDPLATFORM): the release
# bundles ERTS and OTP's crypto NIF, which are arch-specific. CI builds each
# arch on a native runner; a local cross build runs this stage under QEMU.
FROM buildpack-deps:stable-scm@sha256:494c8cd78eee342bcab52bf7d31d77755aaa770f5d8e668685def8f7b8d34d77 AS matrix2051-builder

ARG MATRIX2051_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    MIX_ENV=prod
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /build

# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      elixir erlang-nox erlang-dev ca-certificates

RUN git init -q matrix2051 && \
    git -C matrix2051 fetch -q --depth=1 \
      https://github.com/progval/matrix2051.git "${MATRIX2051_VERSION}" && \
    git -C matrix2051 -c advice.detachedHead=false checkout -q FETCH_HEAD

WORKDIR /build/matrix2051
# Fix carried until it's upstream: on connect, also read state events from the
# sync timeline, where spec-compliant servers such as tuwunel put a small room's
# alias and members. git apply fails the build if upstream changes that code.
COPY patches/matrix2051-*.patch /build/patches/
RUN git apply /build/patches/matrix2051-*.patch

# Listen on 127.0.0.1 only (upstream binds every interface): stunnel is the
# only way in, so plaintext IRC is never exposed, same as BitlBee. Guarded so
# an upstream change fails the build instead of silently exposing the port.
RUN grep -q '^      :inet6,$' lib/irc_server.ex && \
    sed -i 's/^      :inet6,$/      ip: {127, 0, 0, 1},/' lib/irc_server.ex && \
    mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod && \
    mix release --path /opt/matrix2051

############################
# Builder stage
############################
FROM --platform=$BUILDPLATFORM buildpack-deps:stable-scm@sha256:494c8cd78eee342bcab52bf7d31d77755aaa770f5d8e668685def8f7b8d34d77 AS builder

ARG BITLBEE_VERSION
ARG S6_OVERLAY_VERSION
ARG TUWUNEL_VERSION
ARG MAUTRIX_META_VERSION
ARG PURPLE_DISCORD_VERSION
ARG PURPLE_TEAMS_VERSION
ARG PURPLE_GOOGLECHAT_VERSION
ARG BITLBEE_MASTODON_VERSION
ARG PURPLE_WHATSMEOW_VERSION
ARG WHATSMEOW_VERSION

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
    netcat-traditional curl ca-certificates golang gettext sudo zstd

# Fetch all sources in parallel where possible. fetch_commit DIR URL SHA
# checks out one pinned commit (git clone --branch takes no SHA).
RUN --mount=type=cache,target=/root/.cache/go-build \
    fetch_commit() { \
      git init -q "$1" && \
      git -C "$1" fetch -q --depth=1 "$2" "$3" && \
      git -C "$1" -c advice.detachedHead=false checkout -q FETCH_HEAD; \
    }; \
    pids=; \
    curl -fsSL -o bitlbee.tar.gz https://get.bitlbee.org/src/bitlbee-${BITLBEE_VERSION}.tar.gz & pids="$pids $!"; \
    fetch_commit purple-discord https://github.com/EionRobb/purple-discord.git "${PURPLE_DISCORD_VERSION}" & pids="$pids $!"; \
    fetch_commit purple-teams https://github.com/EionRobb/purple-teams.git "${PURPLE_TEAMS_VERSION}" & pids="$pids $!"; \
    fetch_commit purple-googlechat https://github.com/EionRobb/purple-googlechat.git "${PURPLE_GOOGLECHAT_VERSION}" & pids="$pids $!"; \
    git clone --depth=1 --single-branch --branch ${BITLBEE_MASTODON_VERSION} https://github.com/kensanata/bitlbee-mastodon.git & pids="$pids $!"; \
    git clone --depth=1 --single-branch --recurse-submodules --shallow-submodules \
      --branch ${PURPLE_WHATSMEOW_VERSION} https://github.com/hoehermann/purple-gowhatsapp.git purple-whatsmeow & pids="$pids $!"; \
    # A bare wait returns 0 whatever the jobs did: check each, so a pinned SHA
    # that vanished (upstream force-push) fails here, not later in make.
    for p in $pids; do wait "$p" || exit 1; done

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

# Download tuwunel (Matrix homeserver) and mautrix-meta (Facebook bridge).
# tuwunel ships zstd-compressed static binaries; x86_64-v1 runs on any x86_64 CPU.
RUN case "${TARGETARCH}" in \
      amd64) TUWUNEL_ARCH="x86_64-v1" ; MM_ARCH="amd64" ;; \
      arm64) TUWUNEL_ARCH="aarch64-v8" ; MM_ARCH="arm64"  ;; \
      *) echo "Unsupported arch: ${TARGETARCH}"; exit 1   ;; \
    esac && \
    curl -fsSL \
      "https://github.com/matrix-construct/tuwunel/releases/download/v${TUWUNEL_VERSION}/v${TUWUNEL_VERSION}-release-all-${TUWUNEL_ARCH}-linux-gnu-tuwunel.zst" \
      | zstd -d -o /usr/local/bin/tuwunel && \
    chmod +x /usr/local/bin/tuwunel && \
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
# Pin whatsmeow (see WHATSMEOW_VERSION). Guarded so a changed go.mod.in fails the build.
RUN grep -q '^\s*go.mau.fi/whatsmeow latest$' purple-whatsmeow/go.mod.in && \
    sed -i "s|^\(\s*go.mau.fi/whatsmeow\) latest$|\1 ${WHATSMEOW_VERSION}|" purple-whatsmeow/go.mod.in && \
    grep -q "go.mau.fi/whatsmeow ${WHATSMEOW_VERSION}" purple-whatsmeow/go.mod.in
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
FROM debian:stable-slim@sha256:9e3624ad785d0d322f0c69194c2c0ebba7bc5fda3e2c6523ac095b4f08a12ba7

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

# matrix2051: self-contained Elixir release (bundles ERTS)
COPY --from=matrix2051-builder /opt/matrix2051 /opt/matrix2051
COPY --chmod=755 scripts/matrix-register /usr/local/bin/matrix-register

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
    ls -la "${ARCH_DIR}/purple-2/" || echo "Warning: No plugins found" && \
    # Sanity check: fail the build if the downloaded tuwunel binary can't run here
    tuwunel --version

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

# Health check script — checks the TLS ports only; plaintext is loopback-internal
COPY --chmod=755 <<'EOF' /usr/local/bin/healthcheck.sh
#!/bin/sh
nc -z localhost 6697 || exit 1
nc -z localhost 6698 || exit 1
EOF

# Entrypoint: first-run init script, run by s6-overlay before services start
COPY --chmod=755 entrypoint.sh /etc/cont-init.d/10-init.sh

VOLUME ["/var/lib/bitlbee"]

WORKDIR /var/lib/bitlbee

EXPOSE 6697 6698

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD ["/usr/local/bin/healthcheck.sh"]

# Bundled component versions, readable with:
#   docker inspect -f '{{json .Config.Labels}}' mbologna/docker-bitlbee:<tag>
# Declared here, at the end, so a version bump doesn't invalidate the layers above.
ARG TDLIB_PURPLE_VERSION
ARG BITLBEE_VERSION
ARG S6_OVERLAY_VERSION
ARG TUWUNEL_VERSION
ARG MAUTRIX_META_VERSION
ARG MATRIX2051_VERSION
ARG PURPLE_DISCORD_VERSION
ARG PURPLE_TEAMS_VERSION
ARG PURPLE_GOOGLECHAT_VERSION
ARG BITLBEE_MASTODON_VERSION
ARG PURPLE_WHATSMEOW_VERSION
LABEL org.opencontainers.image.title="BitlBee container" \
      org.opencontainers.image.description="A containerized version of BitlBee with additional plugins." \
      org.opencontainers.image.url="https://github.com/mbologna/docker-bitlbee" \
      org.opencontainers.image.licenses="MIT" \
      io.github.mbologna.docker-bitlbee.tdlib-purple.version="${TDLIB_PURPLE_VERSION}" \
      io.github.mbologna.docker-bitlbee.bitlbee.version="${BITLBEE_VERSION}" \
      io.github.mbologna.docker-bitlbee.s6-overlay.version="${S6_OVERLAY_VERSION}" \
      io.github.mbologna.docker-bitlbee.tuwunel.version="${TUWUNEL_VERSION}" \
      io.github.mbologna.docker-bitlbee.mautrix-meta.version="${MAUTRIX_META_VERSION}" \
      io.github.mbologna.docker-bitlbee.matrix2051.version="${MATRIX2051_VERSION}" \
      io.github.mbologna.docker-bitlbee.purple-discord.version="${PURPLE_DISCORD_VERSION}" \
      io.github.mbologna.docker-bitlbee.purple-teams.version="${PURPLE_TEAMS_VERSION}" \
      io.github.mbologna.docker-bitlbee.purple-googlechat.version="${PURPLE_GOOGLECHAT_VERSION}" \
      io.github.mbologna.docker-bitlbee.bitlbee-mastodon.version="${BITLBEE_MASTODON_VERSION}" \
      io.github.mbologna.docker-bitlbee.purple-whatsmeow.version="${PURPLE_WHATSMEOW_VERSION}"

# s6-overlay is PID 1 — handles init, zombie reaping, and service supervision
ENTRYPOINT ["/init"]
