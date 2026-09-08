ARG BUILD_FROM
FROM ${BUILD_FROM} AS base

ENV LANG=C.UTF-8
ARG BUILD_VERSION

RUN apk add --no-cache socat tini nodejs eudev && curl --version

FROM base AS dependencies_and_build

RUN apk add --no-cache --virtual .buildtools npm make gcc g++ linux-headers udev git python3 && \
    curl -fsSL -o /app.tar.gz "https://github.com/Koenkk/zigbee2mqtt/archive/${BUILD_VERSION%-ihost.*}.tar.gz" && \
    tar -xzf /app.tar.gz && rm /app.tar.gz && \
    mv "zigbee2mqtt-${BUILD_VERSION%-ihost.*}" /app && \
    mkdir /app/dist && jq -n --arg commit "${BUILD_VERSION%-ihost.*}" '$commit' > /app/dist/.hash && \
    cd /app && \
    npm install -g "$(jq -r '.packageManager' package.json)" && \
    pnpm install --frozen-lockfile --unsafe-perm && \
    pnpm run build && \
    rm -rf node_modules && \
    pnpm install --frozen-lockfile --no-optional --unsafe-perm --prod && \
    find ./node_modules/.pnpm/ -wholename '*/@serialport/bindings-cpp/prebuilds' -type d -prune -exec rm -rf {} + && \
    pnpm rebuild @serialport/bindings-cpp

FROM base AS release
WORKDIR /app
COPY rootfs /
COPY --from=dependencies_and_build /app/node_modules ./node_modules
COPY --from=dependencies_and_build /app/dist ./dist
COPY --from=dependencies_and_build /app/package.json /app/LICENSE /app/index.js ./
RUN chmod 0755 /docker-entrypoint.sh
ENV NODE_ENV=production
HEALTHCHECK --interval=1m --timeout=3s --start-period=30s --start-interval=3s CMD curl -f http://localhost:8099/
ENTRYPOINT ["/sbin/tini", "--", "/docker-entrypoint.sh"]
