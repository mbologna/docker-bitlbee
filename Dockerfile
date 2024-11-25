FROM docker.io/buildpack-deps:bookworm-scm AS builder

LABEL org.opencontainers.image.title="BitlBee Docker container" \
    org.opencontainers.image.description="A containerized version of BitlBee with additional plugins." \
    org.opencontainers.image.url="https://github.com/michelebologna/docker-bitlbee" \
    org.opencontainers.image.licenses="MIT"

ENV BITLBEE_VERSION=3.6
ENV BITLBEE_HOME=/usr/local/etc/bitlbee

COPY build.sh /root/
RUN chmod +x /root/build.sh && /root/build.sh

# Define volumes for persistent data
VOLUME ["/var/lib/bitlbee"]

EXPOSE 6667

USER bitlbee

# Needed for VOLUME permissions
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["/usr/sbin/bitlbee", "-D", "-n", "-v", "-u", "bitlbee"]
