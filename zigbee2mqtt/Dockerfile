FROM ghcr.io/koenkk/zigbee2mqtt:2.14.1

# The official Zigbee2MQTT image is multi-architecture, including linux/arm/v7.
# This wrapper only supplies Home Assistant add-on option handling.
RUN apk add --no-cache curl jq socat && \
    node -e "const [major] = process.versions.node.split('.').map(Number); if (major < 22) process.exit(1); console.log(process.version, process.arch)"

COPY rootfs/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 0755 /docker-entrypoint.sh
HEALTHCHECK --interval=1m --timeout=3s --start-period=30s --start-interval=3s CMD curl -f http://localhost:8099/
ENTRYPOINT ["/sbin/tini", "--", "/docker-entrypoint.sh"]
