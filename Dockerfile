FROM fedora:latest
MAINTAINER Michele Bologna <michele.bologna@gmail.com>

ENV VERSION=3.4.1

RUN dnf -y install tar gcc make gnutls-devel glib2-devel \
libgcrypt-devel libotr-devel && \
cd && \
curl -LO# http://get.bitlbee.org/src/bitlbee-$VERSION.tar.gz && \
tar zxvf bitlbee-$VERSION.tar.gz && \
cd bitlbee-$VERSION && \
./configure --otr=1 --skype=1 && \
make && \
make install && \
make install-etc && \
dnf -y erase tar && \
dnf clean all && \
cd && \
rm -fr bitlbee-$VERSION* && \
mkdir -p /var/lib/bitlbee && \
chown -R daemon:daemon /var/lib/bitlbee* # dup: otherwise it won't be chown'ed when using volumes

ADD etc/bitlbee/bitlbee.conf /usr/local/etc/bitlbee/bitlbee.conf
ADD etc/bitlbee/motd.txt /usr/local/etc/bitlbee/motd.txt

VOLUME ["/var/lib/bitlbee"]
RUN touch /var/run/bitlbee.pid && \
	chown daemon:daemon /var/run/bitlbee.pid && \
	chown -R daemon:daemon /usr/local/etc/* && \
	chown -R daemon:daemon /var/lib/bitlbee*  # dup: otherwise it won't be chown'ed when using volumes
USER daemon
EXPOSE 6667
CMD ["/usr/local/sbin/bitlbee", "-c", "/usr/local/etc/bitlbee/bitlbee.conf", "-n", "-u", "daemon"]

