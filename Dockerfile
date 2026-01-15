# syntax=docker/dockerfile:1.7

############################
# 1️⃣ Builder stage
############################
FROM buildpack-deps:stable-scm AS builder

LABEL org.opencontainers.image.title="BitlBee container" \
      org.opencontainers.image.description="A containerized version of BitlBee with additional plugins." \
      org.opencontainers.image.url="https://github.com/mbologna/docker-bitlbee" \
      org.opencontainers.image.licenses="MIT"

ARG BITLBEE_VERSION=3.6
ARG SKYPE4PIDGIN_VERSION=1.7
ARG FACEBOOK_VERSION=1.2.2

ENV DEBIAN_FRONTEND=noninteractive
ENV LDFLAGS="-lgcrypt"

WORKDIR /build

# ---- Build dependencies (single layer, cache-friendly)
RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf automake build-essential cmake gettext git gperf \
    imagemagick libtool libtool-bin make pkg-config sudo \
    libglib2.0-dev libhttp-parser-dev libotr5-dev libpurple-dev \
    libgnutls28-dev libjson-glib-dev libnss3-dev libpng-dev \
    libolm-dev libprotobuf-c-dev protobuf-c-compiler \
    libqrencode-dev libssl-dev libgcrypt20-dev \
    libmarkdown2-dev librsvg2-bin libsqlite3-dev \
    libwebp-dev libgdk-pixbuf-xlib-2.0-dev libopusfile-dev \
    netcat-traditional curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ---- Fetch sources
RUN curl -fsSLO https://get.bitlbee.org/src/bitlbee-${BITLBEE_VERSION}.tar.gz \
 && curl -fsSLO https://github.com/EionRobb/skype4pidgin/archive/${SKYPE4PIDGIN_VERSION}.tar.gz \
 && curl -fsSLO https://github.com/bitlbee/bitlbee-facebook/archive/v${FACEBOOK_VERSION}.tar.gz \
 && git clone --depth=1 https://github.com/EionRobb/purple-hangouts.git \
 && git clone --depth=1 https://github.com/EionRobb/purple-discord.git \
 && git clone --depth=1 https://github.com/matrix-org/purple-matrix.git \
 && git clone --depth=1 https://github.com/EionRobb/purple-teams.git \
 && git clone --depth=1 https://github.com/dylex/slack-libpurple.git \
 && git clone --depth=1 https://src.alexschroeder.ch/bitlbee-mastodon.git \
 && git clone --depth=1 https://github.com/BenWiederhake/tdlib-purple.git

# ---- Build BitlBee
RUN tar xf bitlbee-${BITLBEE_VERSION}.tar.gz \
 && cd bitlbee-${BITLBEE_VERSION} \
 && ./configure --jabber=1 --otr=1 --purple=1 --strip=1 \
 && make -j$(nproc) \
 && make install install-bin install-doc install-dev install-etc install-plugin-otr

# ---- Build libpurple plugins
RUN for d in purple-hangouts purple-discord purple-matrix purple-teams; do \
      cd /build/$d && make -j$(nproc) && make install; \
    done

RUN cd /build/slack-libpurple && make install

RUN tar xf ${SKYPE4PIDGIN_VERSION}.tar.gz \
 && cd skype4pidgin-${SKYPE4PIDGIN_VERSION}/skypeweb \
 && make -j$(nproc) && make install

RUN tar xf v${FACEBOOK_VERSION}.tar.gz \
 && cd bitlbee-facebook-${FACEBOOK_VERSION} \
 && ./autogen.sh && make -j$(nproc) && make install

RUN cd bitlbee-mastodon \
 && ./autogen.sh \
 && ./configure \
 && make -j$(nproc) && make install

RUN cd tdlib-purple && ./build_and_install.sh

RUN libtool --finish /usr/local/lib/bitlbee

############################
# 2️⃣ Runtime stage
############################
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpurple0 libotr5 libssl3 libgnutls30 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ---- Copy only what is needed
COPY --from=builder /usr/local /usr/local
COPY --from=builder /usr/lib/x86_64-linux-gnu/purple-2 /usr/lib/x86_64-linux-gnu/purple-2

# ---- Runtime user
RUN adduser --system \
    --home /var/lib/bitlbee \
    --disabled-login \
    --shell /usr/sbin/nologin \
    bitlbee \
 && install -o bitlbee -g nogroup -m 644 /dev/null /var/run/bitlbee.pid

# ---- Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

VOLUME ["/var/lib/bitlbee"]

USER bitlbee
EXPOSE 6667

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/local/sbin/bitlbee", "-F", "-n", "-v", "-u", "bitlbee"]
