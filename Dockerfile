FROM buildpack-deps:stretch-curl
MAINTAINER Michele Bologna <michele.bologna@gmail.com>

ENV VERSION=3.5.1

RUN apt-get update && apt-get install -y --no-install-recommends autoconf automake gettext gcc libtool make dpkg-dev libglib2.0-dev libotr5-dev libpurple-dev libgnutls28-dev libjson-glib-dev libprotobuf-c-dev protobuf-c-compiler mercurial libgcrypt20 libgcrypt20-dev libwebp-dev git && \
cd && \
curl -LO# https://get.bitlbee.org/src/bitlbee-$VERSION.tar.gz && \
curl -LO# https://github.com/EionRobb/skype4pidgin/archive/1.4.tar.gz && \
curl -LO# https://github.com/majn/telegram-purple/releases/download/v1.3.1/telegram-purple_1.3.1.orig.tar.gz && \
curl -LO# https://github.com/jgeboski/bitlbee-facebook/archive/v1.1.2.tar.gz && \
hg clone https://bitbucket.org/EionRobb/purple-hangouts/ && \
git clone https://alexschroeder.ch/cgit/bitlbee-mastodon && \
tar zxvf bitlbee-$VERSION.tar.gz && \
cd bitlbee-$VERSION && \
./configure --jabber=1 --otr=1 --purple=1 && \
make && \
make install && \
make install-etc && \
make install-dev && \
# install skypeweb
cd && \
tar zxvf 1.4.tar.gz && \
cd skype4pidgin-1.4/skypeweb && \
make && \
make install && \
# install telegram purple
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
cd && \
cd purple-hangouts && \
make && \
make install && \
# install bitlbee-mastodon
cd && \
cd bitlbee-mastodon && \
./autogen.sh && \
./configure --prefix=/usr && \
make && \
make install && \
# cleanup
apt-get autoremove -y --purge autoconf automake gcc libtool make dpkg-dev mercurial && \
apt-get clean && \
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /tmp/* && \
cd && \
rm -fr bitlbee-$VERSION* && \
rm -fr 1.4.tar.gz skype4pidgin-* && \
rm -fr v1.1.2.tar.gz bitlbee-facebook-* && \
rm -fr purple-hangouts && \
rm -fr telegram-purple_1.3.1.orig.tar.gz && \
rm -fr telegram-purple && \
rm -rf bitlbee-mastodon && \
mkdir -p /var/lib/bitlbee && \
chown -R daemon:daemon /var/lib/bitlbee* # dup: otherwise it won't be chown'ed when using volumes

COPY etc/bitlbee/bitlbee.conf /usr/local/etc/bitlbee/bitlbee.conf
COPY etc/bitlbee/motd.txt /usr/local/etc/bitlbee/motd.txt

VOLUME ["/var/lib/bitlbee"]
RUN touch /var/run/bitlbee.pid && \
	chown daemon:daemon /var/run/bitlbee.pid && \
	chown -R daemon:daemon /usr/local/etc/* && \
	chown -R daemon:daemon /var/lib/bitlbee*  # dup: otherwise it won't be chown'ed when using volumes
USER daemon
EXPOSE 6667
CMD ["/usr/local/sbin/bitlbee", "-c", "/usr/local/etc/bitlbee/bitlbee.conf", "-n", "-u", "daemon"]

