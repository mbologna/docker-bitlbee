#!/bin/bash

set -e  # Exit script on any error

# Function to install a package from source
install_package() {
    local dir="$1"
    echo "Installing $dir..."
    cd "$dir" && make && make install && cd ..
}

# Install BitlBee dependencies
echo "Installing build dependencies..."
apt-get update && apt-get install -y --no-install-recommends \
    autoconf automake build-essential cmake g++ gettext gcc git \
    gperf imagemagick libtool make libglib2.0-dev libhttp-parser-dev \
    libotr5-dev libpurple-dev libgnutls28-dev libjson-glib-dev libnss3-dev \
    libpng-dev libolm-dev libprotobuf-c-dev libqrencode-dev libssl-dev \
    protobuf-c-compiler libgcrypt20-dev libmarkdown2-dev \
    libpng-dev libpurple-dev librsvg2-bin libsqlite3-dev libwebp-dev \
    libgdk-pixbuf2.0-dev libopusfile-dev \
    libtool-bin pkg-config sudo

# Download sources for BitlBee and plugins
echo "Downloading sources..."
curl -LO https://get.bitlbee.org/src/bitlbee-$BITLBEE_VERSION.tar.gz
curl -LO https://github.com/EionRobb/skype4pidgin/archive/1.7.tar.gz
git clone https://github.com/BenWiederhake/tdlib-purple
curl -LO https://github.com/bitlbee/bitlbee-facebook/archive/v1.2.2.tar.gz
git clone https://github.com/EionRobb/purple-hangouts
git clone https://src.alexschroeder.ch/bitlbee-mastodon.git
git clone https://github.com/EionRobb/purple-discord
git clone https://github.com/dylex/slack-libpurple
git clone https://github.com/matrix-org/purple-matrix
git clone https://github.com/EionRobb/purple-teams


# Install BitlBee
echo "Building and installing BitlBee..."
tar zxvf bitlbee-$BITLBEE_VERSION.tar.gz
cd bitlbee-$BITLBEE_VERSION
./configure --jabber=1 --otr=1 --purple=1 --ssl=openssl --prefix=/usr --etcdir=/etc/bitlbee
make
make install
make install-bin
make install-doc
make install-dev
make install-etc
cd ..

# Install other plugins
tar zxvf 1.7.tar.gz && install_package "skype4pidgin-1.7/skypeweb" && cd ..
cd "tdlib-purple" && ./build_and_install.sh && cd ..
tar zxvf v1.2.2.tar.gz && cd "bitlbee-facebook-1.2.2" && ./autogen.sh && make && make install && cd ..
install_package "purple-hangouts"
cd "bitlbee-mastodon" && sh autogen.sh && ./configure && make && make install && cd ..
install_package "purple-discord"
install_package "slack-libpurple"
install_package "purple-matrix"
install_package "purple-teams"

# Final setup for BitlBee
libtool --finish /usr/lib/bitlbee

# Clean up
echo "Cleaning up unnecessary packages..."
apt-get autoremove --purge -y
apt-get remove -y --purge autoconf automake autotools-dev binutils \
    build-essential bzip2 cmake cpp* dpkg-dev gettext gettext-base \
    imagemagick libbinutils libgcc-*-dev libnss3-dev libopusfile-dev \
    libqrencode-dev librsvg2-bin \
    libsqlite3-dev libstdc++-*-dev libtasn1-*-dev libtool libtool-bin \
    m4 make nettle-dev patch xz-utils
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Remove temporary files and downloaded sources
echo "Removing temporary files..."
rm -fr /root/build.sh
rm -fr bitlbee-$BITLBEE_VERSION*
rm -fr 1.7.tar.gz skype4pidgin-*
rm -fr tdlib-purple*
rm -fr v1.2.2.tar.gz bitlbee-facebook-*
rm -fr purple-hangouts
rm -rf bitlbee-mastodon
rm -fr purple-discord*
rm -fr slack-libpurple
rm -fr purple-matrix
rm -fr purple-teams

# Add user for BitlBee
echo "Adding user bitlbee..."
adduser --system --home /var/lib/bitlbee --disabled-password \
    --disabled-login --shell /usr/sbin/nologin bitlbee

# Create a necessary PID file
touch /var/run/bitlbee.pid && chown bitlbee:nogroup /var/run/bitlbee.pid
