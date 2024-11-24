# Use a more specific base image for better consistency
FROM docker.io/buildpack-deps:bookworm-scm AS builder

# Combine LABELs to reduce layers
LABEL maintainer="Michele Bologna <github@michelebologna.net>" \
    name="BitlBee Docker container by Michele Bologna" \
    version="mb-3.6-20241123"

# Set environment variables
ENV BITLBEE_VERSION=3.6
ENV BITLBEE_HOME=/usr/local/etc/bitlbee

# Copy the build script and run it
COPY build.sh /root/
RUN chmod +x /root/build.sh && /root/build.sh

# Define volumes for persistent data
VOLUME ["/var/lib/bitlbee"]

# Expose necessary port for BitlBee
EXPOSE 6667

# Run as non-root user for security
USER bitlbee

# Set the entrypoint for BitlBee
ENTRYPOINT ["/usr/sbin/bitlbee"]

# Provide default command arguments
CMD ["/usr/sbin/bitlbee", "-D", "-n", "-v"]
