FROM buildpack-deps:jessie-curl
MAINTAINER Michele Bologna <michele.bologna@gmail.com>

ENV VERSION=3.4.2

RUN apt-get update && apt-get install -y --no-install-recommends autoconf automake gettext gcc libtool make dpkg-dev libglib2.0-dev libotr5-dev libpurple-dev libgnutls28-dev libjson-glib-dev && \
cd && \
curl -LO# https://get.bitlbee.org/src/bitlbee-$VERSION.tar.gz && \
curl -LO# https://github.com/EionRobb/skype4pidgin/archive/1.2.2.tar.gz && \
curl -LO# https://github.com/jgeboski/bitlbee-facebook/archive/v1.0.0.tar.gz && \
tar zxvf bitlbee-$VERSION.tar.gz && \
cd bitlbee-$VERSION && \
./configure --jabber=1 --otr=1 --purple=1 && \
make && \
make install && \
make install-etc && \
make install-dev && \
cd && \
tar zxvf 1.2.2.tar.gz && \
cd skype4pidgin-1.2.2/skypeweb && \
make && \
make install && \
cd && \
tar zxvf v1.0.0.tar.gz && \
cd bitlbee-facebook-1.0.0 && \
./autogen.sh && \
make && \
make install && \
apt-get autoremove -y --purge autoconf automake gcc libtool make dpkg-dev && \
apt-get clean && \
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /tmp/* && \
cd && \
rm -fr bitlbee-$VERSION* && \
rm -fr 1.2.2.tar.gz skype4pidgin-* && \
rm -fr v1.0.0.tar.gz bitlbee-facebook-* && \
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

