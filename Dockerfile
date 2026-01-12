FROM docker.io/buildpack-deps:stable-scm AS builder

LABEL org.opencontainers.image.title="BitlBee container" \
    org.opencontainers.image.description="A containerized version of BitlBee with additional plugins." \
    org.opencontainers.image.url="https://github.com/mbologna/docker-bitlbee" \
    org.opencontainers.image.licenses="MIT"

ENV BITLBEE_VERSION="3.6" SKYPE4PIDGIN_VERSION="1.7" FACEBOOK_VERSION="1.2.2"

WORKDIR "/"
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    autoconf automake build-essential cmake g++ gettext gcc git \
    gperf imagemagick libtool make libglib2.0-dev libhttp-parser-dev \
    libotr5-dev libpurple-dev libgnutls28-dev libjson-glib-dev libnss3-dev \
    libpng-dev libolm-dev libprotobuf-c-dev libqrencode-dev libssl-dev \
    protobuf-c-compiler libgcrypt20-dev libmarkdown2-dev \
    libpng-dev libpurple-dev librsvg2-bin libsqlite3-dev libwebp-dev \
    libgdk-pixbuf2.0-dev libopusfile-dev \
    libtool-bin netcat-traditional pkg-config sudo && \
    curl -LO https://get.bitlbee.org/src/bitlbee-"$BITLBEE_VERSION".tar.gz && \
    git clone https://github.com/EionRobb/purple-hangouts && \
    git clone https://github.com/EionRobb/purple-discord && \
    git clone https://github.com/matrix-org/purple-matrix && \
    git clone https://github.com/EionRobb/purple-teams && \
    git clone https://github.com/dylex/slack-libpurple && \
    curl -LO https://github.com/EionRobb/skype4pidgin/archive/"$SKYPE4PIDGIN_VERSION".tar.gz && \
    curl -LO https://github.com/bitlbee/bitlbee-facebook/archive/v"$FACEBOOK_VERSION".tar.gz && \
    git clone https://src.alexschroeder.ch/bitlbee-mastodon.git && \
    git clone https://github.com/BenWiederhake/tdlib-purple && \
    rm -fr /var/lib/apt/lists/*

RUN tar zxvf bitlbee-"$BITLBEE_VERSION".tar.gz
WORKDIR /bitlbee-"$BITLBEE_VERSION"
ENV LDFLAGS "-lgcrypt"
RUN ./configure --verbose=1 --jabber=1 --otr=1 --purple=1 --strip=1 && \
    make -j"$(nproc)" && \
    make install && \
    make install-bin && \
    make install-doc && \
    make install-dev && \
    make install-etc && \
    make install-plugin-otr

WORKDIR /purple-hangouts
RUN make -j"$(nproc)" && make install
WORKDIR /purple-discord
RUN make -j"$(nproc)" && make install
WORKDIR /purple-matrix
RUN make -j"$(nproc)" && make install
WORKDIR /purple-teams
RUN make -j"$(nproc)" && make install
WORKDIR /slack-libpurple
RUN make install
WORKDIR /
RUN tar zxvf "$SKYPE4PIDGIN_VERSION".tar.gz
WORKDIR /skype4pidgin-$SKYPE4PIDGIN_VERSION/skypeweb
RUN make -j"$(nproc)" && make install
WORKDIR /
RUN tar zxvf v"$FACEBOOK_VERSION".tar.gz
WORKDIR /bitlbee-facebook-$FACEBOOK_VERSION
RUN ./autogen.sh && make -j"$(nproc)" && make install
WORKDIR /bitlbee-mastodon
RUN sh autogen.sh && ./configure && make -j"$(nproc)" && make install
WORKDIR /tdlib-purple
RUN ./build_and_install.sh

WORKDIR /
RUN libtool --finish /usr/local/lib/bitlbee

RUN rm -fr ./bitlbee-"$BITLBEE_VERSION" && \
    rm -fr ./purple* && \
    rm -fr ./slack-libpurple && \
    rm -fr ./skype4pidgin* && \
    rm -fr ./bitlbee-facebook* && \
    rm -fr ./bitlbee-mastodon* && \
    rm -fr ./tdlib-purple && \
    rm -fr -- *.gz && \
    apt-get clean && \
    rm -fr /tmp/* /var/tmp/*

# FROM docker.io/debian:stable-slim

# COPY --from=builder /usr/local/etc/bitlbee/ /usr/local/etc/bitlbee/
# COPY --from=builder /usr/local/lib/bitlbee/ /usr/local/lib/bitlbee/
# COPY --from=builder /usr/local/lib/pkgconfig/ /usr/local/lib/pkgconfig/
# COPY --from=builder /usr/lib/x86_64-linux-gnu/purple-2/libdiscord.so /usr/lib/x86_64-linux-gnu/purple-2/libdiscord.so
# COPY --from=builder /usr/lib/x86_64-linux-gnu/purple-2/libhangouts.so /usr/lib/x86_64-linux-gnu/purple-2/libhangouts.so
# COPY --from=builder /usr/lib/x86_64-linux-gnu/purple-2/libmatrix.so /usr/lib/x86_64-linux-gnu/purple-2/libmatrix.so
# COPY --from=builder /usr/lib/x86_64-linux-gnu/purple-2/libskypeweb.so /usr/slib/x86_64-linux-gnu/purple-2/libskypeweb.so
# COPY --from=builder /usr/lib/x86_64-linux-gnu/purple-2/libslack.so /usr/lib/x86_64-linux-gnu/purple-2/libslack.so
# COPY --from=builder /usr/lib/x86_64-linux-gnu/purple-2/libteams-personal.so /usr/lib/x86_64-linux-gnu/purple-2/libteams-personal.so
# COPY --from=builder /usr/lib/x86_64-linux-gnu/purple-2/libteams.so /usr/lib/x86_64-linux-gnu/purple-2/libteams.so
# COPY --from=builder /usr/lib/x86_64-linux-gnu/purple-2/libtelegram-tdlib.so /usr/lib/x86_64-linux-gnu/purple-2/libtelegram-tdlib.so
# COPY --from=builder /usr/local/sbin/bitlbee /usr/local/sbin/bitlbee
# COPY --from=builder /usr/local/share/bitlbee/ /usr/local/share/bitlbee/
# COPY --from=builder /usr/local/share/locale/ /usr/local/share/locale/
# COPY --from=builder /usr/local/share/man/ /usr/local/share/man/
# COPY --from=builder /usr/local/share/metainfo/ /usr/local/share/metainfo/

# RUN apt-get update && apt-get install --no-install-recommends -y \
#     libpurple0 \
#     libotr5

RUN adduser --system --home /var/lib/bitlbee --disabled-password \
    --disabled-login --shell /usr/sbin/nologin bitlbee
RUN touch /var/run/bitlbee.pid && chown bitlbee:nogroup /var/run/bitlbee.pid

EXPOSE 6667

# Needed for VOLUME permissions
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x entrypoint.sh

# Define volumes for persistent data
VOLUME ["/var/lib/bitlbee"]
USER bitlbee
ENTRYPOINT ["/entrypoint.sh"]

CMD ["/usr/local/sbin/bitlbee", "-F", "-n", "-v", "-u", "bitlbee"]
