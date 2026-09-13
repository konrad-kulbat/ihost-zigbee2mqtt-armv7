#!/usr/bin/env bash
# Runs against a linux/arm/v7 image under QEMU on an amd64 CI runner.
set -Eeuo pipefail
IMAGE="${1:-ihost-zigbee2mqtt-armv7:test}"
NETWORK=z2m-test-net; Z2M=z2m-test; SUPERVISOR_Z2M=z2m-supervisor-test; SOCAT_Z2M=z2m-socat-test
MQTT=mqtt-test; MOCK=mock-supervisor; SUB=z2m-mqtt-sub
WORK_DIR="$(mktemp -d)"; DATA_DIR="$WORK_DIR/data"; NETWORK_CREATED=0
pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
host_path() { command -v cygpath >/dev/null 2>&1 && cygpath -aw "$1" || printf '%s' "$1"; }
readonly_mount() { printf '%s' "--mount=type=bind,src=$(host_path "$1"),dst=$2,readonly"; }
readwrite_mount() { printf '%s' "--mount=type=bind,src=$(host_path "$1"),dst=$2"; }
node_environment() {
  docker exec --user root "$1" sh -ec 'for proc in /proc/[0-9]*; do command=$(tr "\000" " " < "$proc/cmdline" 2>/dev/null || true); executable=$(readlink "$proc/exe" 2>/dev/null || true); case "$executable:$command" in */node:*index.js*) tr "\000" "\n" < "$proc/environ"; exit 0;; esac; done; echo "node index.js process was not found" >&2; exit 1'
}
expect_node_env() { node_environment "$1" | grep -Fx -- "$2" >/dev/null || fail "$1 node environment lacks $2"; }
diagnostics() {
  printf '\n===== diagnostics =====\n' >&2; docker ps -a >&2 || true
  for c in "$Z2M" "$SUPERVISOR_Z2M" "$SOCAT_Z2M" "$MQTT" "$MOCK"; do
    docker container inspect "$c" >/dev/null 2>&1 || continue
    printf '\n----- docker logs %s -----\n' "$c" >&2; docker logs "$c" >&2 || true
  done
  if docker container inspect "$Z2M" >/dev/null 2>&1; then docker inspect -f '{{json .State.Health}}' "$Z2M" >&2 || true; fi
  for c in "$Z2M" "$SUPERVISOR_Z2M"; do docker container inspect "$c" >/dev/null 2>&1 && node_environment "$c" >&2 || true; done
}
cleanup() {
  status=$?; [ "$status" -eq 0 ] || diagnostics
  docker rm -f "$Z2M" "$SUPERVISOR_Z2M" "$SOCAT_Z2M" "$MQTT" "$MOCK" "$SUB" >/dev/null 2>&1 || true
  [ "$NETWORK_CREATED" -eq 0 ] || docker network rm "$NETWORK" >/dev/null 2>&1 || true
  rm -rf "$WORK_DIR"; exit "$status"
}
trap cleanup EXIT
trap 'printf "[FAIL] command failed at line %s: %s\\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
for c in "$Z2M" "$SUPERVISOR_Z2M" "$SOCAT_Z2M" "$MQTT" "$MOCK" "$SUB"; do docker container inspect "$c" >/dev/null 2>&1 && fail "refusing to replace existing container: $c"; done
docker network inspect "$NETWORK" >/dev/null 2>&1 && fail "refusing to replace existing network: $NETWORK"
wait_http() {
  for _ in {1..45}; do status="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18099/ || true)"; { [ "$status" = 200 ] || [ "$status" = 302 ]; } && return; sleep 2; done; fail 'Z2M frontend did not return HTTP 200 or 302'
}
wait_health() {
  for _ in {1..45}; do status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$Z2M")"; [ "$status" = healthy ] && return; [ "$status" = unhealthy ] && fail 'Z2M healthcheck became unhealthy'; sleep 2; done; fail 'Z2M healthcheck did not become healthy'
}
mkdir -p "$DATA_DIR" "$WORK_DIR/socat-data"
printf '%s\n' '{"data_path":"/config/zigbee2mqtt","force_onboarding":true,"socat":{"enabled":false},"mqtt":{"server":"mqtt://mqtt-test:1883","base_topic":"zigbee2mqtt"},"serial":{}}' > "$WORK_DIR/options.json"
printf '%s\n' '{"data_path":"/config/zigbee2mqtt","force_onboarding":true,"socat":{"enabled":false},"mqtt":{},"serial":{}}' > "$WORK_DIR/supervisor-options.json"
printf '%s\n' '{"data_path":"/config/zigbee2mqtt","force_onboarding":true,"socat":{"enabled":true,"master":"PTY,raw,echo=0,link=/tmp/ttyZ2M,mode=777","slave":"TCP-LISTEN:8485,reuseaddr,fork","options":"-d -d","log":true},"mqtt":{"server":"mqtt://mqtt-test:1883"},"serial":{}}' > "$WORK_DIR/socat-options.json"
docker image inspect "$IMAGE" >/dev/null || fail "image not found: $IMAGE"
[ "$(docker image inspect -f '{{.Architecture}}' "$IMAGE")" = arm ] || fail 'image architecture is not ARM'
docker image inspect -f '{{json .Config.Entrypoint}}' "$IMAGE" | grep -F tini >/dev/null || fail 'image does not use tini'
docker run --rm --platform linux/arm/v7 --entrypoint sh "$IMAGE" -ec 'test "$(uname -m)" = armv7l; node --version; command -v jq; command -v curl; command -v socat; test -x /sbin/tini'
pass 'ARMv7 runtime'; pass 'Docker image'; pass 'Node.js'
if docker run --rm --platform linux/arm/v7 --entrypoint /docker-entrypoint.sh "$IMAGE" >/dev/null 2>&1; then fail 'entrypoint accepted missing options.json'; fi
printf '%s\n' '{"socat":{"enabled":false},"mqtt":{},"serial":{}}' > "$WORK_DIR/no-data-path.json"
if docker run --rm --platform linux/arm/v7 "$(readonly_mount "$WORK_DIR/no-data-path.json" /data/options.json)" "$IMAGE" >/dev/null 2>&1; then fail 'entrypoint accepted missing data_path'; fi
pass 'negative options validation'
docker network create "$NETWORK" >/dev/null; NETWORK_CREATED=1
docker run -d --name "$MQTT" --network "$NETWORK" --network-alias mqtt-test eclipse-mosquitto:2 >/dev/null
docker run -d --name "$MOCK" --network "$NETWORK" --network-alias mock-supervisor node:22-alpine node -e 'const http=require("http");const body=JSON.stringify({data:{host:"mqtt-test",port:1883,ssl:false,username:"test-user",password:"test-password"}});http.createServer((req,res)=>{if(req.url!=="/services/mqtt"||req.headers.authorization!=="Bearer test-token"){res.writeHead(401);return res.end();}res.writeHead(200,{"content-type":"application/json"});res.end(body);}).listen(80)' >/dev/null
docker run --rm --network "$NETWORK" eclipse-mosquitto:2 sh -ec 'until nc -z mqtt-test 1883; do sleep 1; done'
SUPERVISOR_RESPONSE=''
for _ in {1..30}; do
  if SUPERVISOR_RESPONSE="$(docker run --rm --network "$NETWORK" curlimages/curl:8.10.1 -fsS -H 'Authorization: Bearer test-token' http://mock-supervisor/services/mqtt 2>/dev/null)"; then break; fi
  sleep 1
done
[ -n "$SUPERVISOR_RESPONSE" ] || fail 'mock Supervisor did not become ready within 30 seconds'
printf '%s' "$SUPERVISOR_RESPONSE" | node -e 'let data="";process.stdin.on("data",chunk=>data+=chunk);process.stdin.on("end",()=>{const mqtt=JSON.parse(data).data;if(mqtt.host!=="mqtt-test"||mqtt.port!==1883)process.exit(1);})'
if docker run --rm --network "$NETWORK" curlimages/curl:8.10.1 -fsS http://mock-supervisor/services/mqtt >/dev/null 2>&1; then fail 'mock Supervisor accepted unauthenticated request'; fi
pass 'MQTT TCP'; pass 'Supervisor API'
docker run -d --name "$Z2M" --platform linux/arm/v7 --network "$NETWORK" -p 18099:8099 "$(readonly_mount "$WORK_DIR/options.json" /data/options.json)" "$(readwrite_mount "$DATA_DIR" /config/zigbee2mqtt)" "$IMAGE" >/dev/null
wait_http; wait_health; docker exec --user root "$Z2M" sh -ec 'nslookup mqtt-test >/dev/null'
expect_node_env "$Z2M" 'ZIGBEE2MQTT_CONFIG_FRONTEND_ENABLED=true'; expect_node_env "$Z2M" 'ZIGBEE2MQTT_CONFIG_FRONTEND_PORT=8099'; expect_node_env "$Z2M" 'ZIGBEE2MQTT_CONFIG_HOMEASSISTANT_ENABLED=true'; expect_node_env "$Z2M" 'ZIGBEE2MQTT_CONFIG_MQTT_BASE_TOPIC=zigbee2mqtt'; expect_node_env "$Z2M" 'ZIGBEE2MQTT_CONFIG_MQTT_SERVER=mqtt://mqtt-test:1883'
pass 'options.json'; pass 'Z2M frontend'; pass 'Z2M healthcheck'
PAYLOAD='{"hello":"armv7"}'
docker run -d --name "$SUB" --network "$NETWORK" eclipse-mosquitto:2 sh -ec 'timeout 20 mosquitto_sub -h mqtt-test -t zigbee2mqtt/test -C 1' >/dev/null; sleep 1
docker run --rm --network "$NETWORK" eclipse-mosquitto:2 mosquitto_pub -h mqtt-test -t zigbee2mqtt/test -m "$PAYLOAD"
[ "$(docker logs "$SUB")" = "$PAYLOAD" ] || fail 'MQTT subscriber did not receive the exact payload'
docker rm -f "$SUB" >/dev/null; pass 'MQTT publish/subscribe'
docker exec --user root "$Z2M" sh -ec 'touch /config/zigbee2mqtt/.ci-test'; docker rm -f "$Z2M" >/dev/null
docker run -d --name "$Z2M" --platform linux/arm/v7 --network "$NETWORK" -p 18099:8099 "$(readonly_mount "$WORK_DIR/options.json" /data/options.json)" "$(readwrite_mount "$DATA_DIR" /config/zigbee2mqtt)" "$IMAGE" >/dev/null
docker exec --user root "$Z2M" test -f /config/zigbee2mqtt/.ci-test; wait_http; pass 'persistence'; pass 'restart'
docker run -d --name "$SUPERVISOR_Z2M" --platform linux/arm/v7 --network "$NETWORK" -e SUPERVISOR=http://mock-supervisor:80 -e SUPERVISOR_TOKEN=test-token "$(readonly_mount "$WORK_DIR/supervisor-options.json" /data/options.json)" "$(readwrite_mount "$DATA_DIR" /config/zigbee2mqtt)" "$IMAGE" >/dev/null
for _ in {1..30}; do node_environment "$SUPERVISOR_Z2M" >/dev/null 2>&1 && break; sleep 1; done
expect_node_env "$SUPERVISOR_Z2M" 'ZIGBEE2MQTT_CONFIG_MQTT_SERVER=mqtt://mqtt-test:1883'; expect_node_env "$SUPERVISOR_Z2M" 'ZIGBEE2MQTT_CONFIG_MQTT_USER=test-user'; expect_node_env "$SUPERVISOR_Z2M" 'ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=test-password'; pass 'Supervisor MQTT discovery'
docker run -d --name "$SOCAT_Z2M" --platform linux/arm/v7 --network "$NETWORK" "$(readonly_mount "$WORK_DIR/socat-options.json" /data/options.json)" "$(readwrite_mount "$WORK_DIR/socat-data" /config/zigbee2mqtt)" "$IMAGE" >/dev/null
for _ in {1..30}; do docker exec --user root "$SOCAT_Z2M" test -e /tmp/ttyZ2M >/dev/null 2>&1 && docker exec --user root "$SOCAT_Z2M" sh -ec 'ps | grep -q [s]ocat' && break; sleep 1; done
docker exec --user root "$SOCAT_Z2M" test -e /tmp/ttyZ2M; docker exec --user root "$SOCAT_Z2M" sh -ec 'ps | grep -q [s]ocat'; pass 'socat smoke test'
node -e 'const c=require("./zigbee2mqtt/config.json");if(!(c.arch.includes("armv7")&&c.uart&&c.udev&&c.hassio_api&&c.ingress&&c.services.includes("mqtt:need")&&c.image.includes("{arch}")&&c.startup==="application"))process.exit(1)'
pass 'config.json'
