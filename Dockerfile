FROM buildpack-deps:stretch-curl
LABEL maintainer="Michele Bologna <mb@michelebologna.net>"
LABEL name="BitlBee Docker container by Michele Bologna"
LABEL version="mb-3.5.1-20190115"

ENV VERSION=3.5.1

RUN apt-get update && \
apt-get install -y --no-install-recommends autoconf automake gettext gcc git libtool make dpkg-dev \
libglib2.0-dev libotr5-dev libpurple-dev libgnutls28-dev \
libjson-glib-dev libprotobuf-c-dev protobuf-c-compiler \
mercurial libgcrypt20 libgcrypt20-dev \
libmarkdown2-dev libwebp-dev libtool-bin && \
cd && \
curl -LO# https://get.bitlbee.org/src/bitlbee-$VERSION.tar.gz && \
curl -LO# https://github.com/EionRobb/skype4pidgin/archive/1.5.tar.gz && \
curl -LO# https://github.com/majn/telegram-purple/releases/download/v1.3.1/telegram-purple_1.3.1.orig.tar.gz && \
curl -LO# https://github.com/bitlbee/bitlbee-facebook/archive/v1.1.2.tar.gz && \
hg clone https://bitbucket.org/EionRobb/purple-hangouts/ && \
git clone https://alexschroeder.ch/cgit/bitlbee-mastodon && \
hg clone https://bitbucket.org/EionRobb/purple-rocketchat && \
curl -LO# https://github.com/sm00th/bitlbee-discord/archive/0.4.2.tar.gz && \
git clone https://github.com/dylex/slack-libpurple.git && \
git clone https://github.com/jgeboski/bitlbee-steam.git && \
# build bitlbee
tar zxvf bitlbee-$VERSION.tar.gz && \
cd bitlbee-$VERSION && \
./configure --jabber=1 --otr=1 --purple=1 && \
make && \
make install && \
make install-dev && \
# install skypeweb
cd && \
tar zxvf 1.5.tar.gz && \
cd skype4pidgin-1.5/skypeweb && \
make && \
make install && \
# install telegram-purple
cd && \
tar zxvf telegram-purple_1.3.1.orig.tar.gz && \
cd telegram-purple && \
./configure && \
make && \
make install && \
# install bitlbee-facebook
cd && \
tar zxvf v1.1.2.tar.gz && \
cd bitlbee-facebook-1.1.2 && \
./autogen.sh && \
make && \
make install && \
# install purple-hangouts
cd && \
cd purple-hangouts && \
make && \
make install && \
# install bitlbee-mastodon
cd && \
cd bitlbee-mastodon && \
./autogen.sh && \
./configure && \
make && \
make install && \
# install purple-rocketchat
cd && \
cd purple-rocketchat && \
make && \
make install && \
# install bitlbee-discord
cd && \
tar zxvf 0.4.2.tar.gz && \
cd bitlbee-discord-0.4.2/ && \
./autogen.sh && \
./configure && \
make && \
make install && \
# install slack-libpurple
cd && \
cd slack-libpurple && \
make install && \
# install bitlbee-steam
cd && \
cd bitlbee-steam && \
./autogen.sh && \
make && \
make install && \
# libtool --finish
libtool --finish /usr/local/lib/bitlbee && \
# cleanup
apt-get autoremove -y --purge autoconf automake gcc libtool make dpkg-dev mercurial git && \
apt-get clean && \
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /tmp/* && \
cd && \
rm -fr bitlbee-$VERSION* && \
rm -fr 1.5.tar.gz skype4pidgin-* && \
rm -fr telegram-purple* && \
rm -fr v1.1.2.tar.gz bitlbee-facebook-* && \
rm -fr purple-hangouts && \
rm -rf bitlbee-mastodon && \
rm -rf purple-rocketchat && \
rm -fr bitlbee-discord-0.4.2/ 0.4.2.tar.gz && \
rm -fr slack-libpurple && \
rm -fr bitlbee-steam && \
# add user bitlbee
adduser --system --home /var/lib/bitlbee --disabled-password --disabled-login --shell /usr/sbin/nologin bitlbee && \
touch /var/run/bitlbee.pid && chown bitlbee:nogroup /var/run/bitlbee.pid

VOLUME ["/usr/local/etc/bitlbee"]
VOLUME ["/var/lib/bitlbee"]
EXPOSE 6667
CMD ["/usr/local/sbin/bitlbee", "-c", "/usr/local/etc/bitlbee/bitlbee.conf", "-n", "-v"]
USER bitlbee
