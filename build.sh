#!/bin/bash

apt update
apt install -y --no-install-recommends autoconf automake build-essential gettext gcc libtool make \
libglib2.0-dev libhttp-parser-dev libotr5-dev libpurple-dev libgnutls28-dev \
libjson-glib-dev libpng-dev libolm-dev libprotobuf-c-dev protobuf-c-compiler \
libgcrypt20-dev libmarkdown2-dev libpurple-dev libsqlite3-dev libwebp-dev libtool-bin

cd
curl -LO# https://get.bitlbee.org/src/bitlbee-$BITLBEE_VERSION.tar.gz
curl -LO# https://github.com/EionRobb/skype4pidgin/archive/1.5.tar.gz
curl -LO# https://github.com/majn/telegram-purple/releases/download/v1.4.3/telegram-purple_1.4.3.orig.tar.gz
curl -LO# https://github.com/bitlbee/bitlbee-facebook/archive/v1.2.0.tar.gz
git clone https://github.com/EionRobb/purple-hangouts.git
git clone https://alexschroeder.ch/cgit/bitlbee-mastodon
git clone https://github.com/EionRobb/purple-rocketchat.git
curl -LO# https://github.com/sm00th/bitlbee-discord/archive/0.4.3.tar.gz
git clone https://github.com/dylex/slack-libpurple.git
git clone https://github.com/jgeboski/bitlbee-steam.git
git clone https://github.com/matrix-org/purple-matrix.git
git clone https://github.com/EionRobb/purple-mattermost.git
git clone https://github.com/EionRobb/purple-instagram.git

# # bitlbee
tar zxvf bitlbee-$BITLBEE_VERSION.tar.gz
cd bitlbee-$BITLBEE_VERSION
./configure --jabber=1 --otr=1 --purple=1
make
make install
make install-dev

# skypeweb
cd
tar zxvf 1.5.tar.gz
cd skype4pidgin-1.5/skypeweb
make
make install

# telegram-purple
cd
tar zxvf telegram-purple_1.4.3.orig.tar.gz
cd telegram-purple
./configure
make
make install

# bitlbee-facebook
cd
tar zxvf v1.2.0.tar.gz
cd bitlbee-facebook-1.2.0
./autogen.sh
make
make install

# purple-hangouts
cd
cd purple-hangouts
make
make install

# bitlbee-mastodon
cd
cd bitlbee-mastodon
sh autogen.sh
./configure
make
make install

# purple-rocketchat
cd
cd purple-rocketchat
make
make install

# bitlbee-discord
cd
tar zxvf 0.4.3.tar.gz
cd bitlbee-discord-0.4.3/
./autogen.sh
./configure
make
make install

# slack-libpurple
cd
cd slack-libpurple
make install

# bitlbee-steam
cd
cd bitlbee-steam
./autogen.sh
make
make install

# purple-matrix
cd
cd purple-matrix
make
make install

# purple-mattermost
cd
cd purple-mattermost
make
make install

# purple-instagram
cd
cd purple-instagram
make
make install

# libtool --finish
libtool --finish /usr/local/lib/bitlbee

# cleanup
apt remove -y --purge autoconf automake autotools-dev binutils binutils-common binutils-x86-64-linux-gnu build-essential \
bzip2 cpp cpp-8 dpkg-dev g++ g++-8 gcc gcc-8 gettext gettext-base libbinutils libgcc-8-dev libsqlite3-dev libstdc++-8-dev \
libtasn1-6-dev libtool libtool-bin m4 make nettle-dev patch xz-utils
apt clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /tmp/*
cd
rm -fr /root/build.sh
rm -fr $BITLBEE_VERSION*
rm -fr 1.5.tar.gz skype4pidgin-*
rm -fr telegram-purple*
rm -fr v1.2.0.tar.gz bitlbee-facebook-*
rm -fr purple-hangouts
rm -rf bitlbee-mastodon
rm -rf purple-rocketchat
rm -fr bitlbee-discord-0.4.3/ 0.4.3.tar.gz
rm -fr slack-libpurple
rm -fr bitlbee-steam
rm -fr purple-matrix
rm -fr purple-mattermost
rm -fr purple-instagram

# add user bitlbee
adduser --system --home /var/lib/bitlbee --disabled-password --disabled-login --shell /usr/sbin/nologin bitlbee
touch /var/run/bitlbee.pid && chown bitlbee:nogroup /var/run/bitlbee.pid
