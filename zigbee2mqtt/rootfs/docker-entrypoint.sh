#!/bin/sh
set -eu

OPTIONS=/data/options.json
[ -r "$OPTIONS" ] || { echo "ERROR: Home Assistant options file $OPTIONS is unavailable"; exit 1; }
option() { jq -r "$1 // empty" "$OPTIONS"; }
option_bool() { [ "$(option "$1")" = "true" ]; }

DATA_PATH="$(option '.data_path')"
[ -n "$DATA_PATH" ] || { echo "ERROR: data_path is required"; exit 1; }
mkdir -p "$DATA_PATH" || { echo "ERROR: could not create $DATA_PATH"; exit 1; }
export ZIGBEE2MQTT_DATA="$DATA_PATH"

if option_bool '.socat.enabled'; then
    SOCAT_MASTER="$(option '.socat.master')"
    SOCAT_SLAVE="$(option '.socat.slave')"
    [ -n "$SOCAT_MASTER" ] && [ -n "$SOCAT_SLAVE" ] || { echo "ERROR: socat enabled but master/slave is empty"; exit 1; }
    SOCAT_OPTIONS="$(option '.socat.options')"
    if option_bool '.socat.log'; then
        socat $SOCAT_OPTIONS "$SOCAT_MASTER" "$SOCAT_SLAVE" >> "$DATA_PATH/socat.log" 2>&1 &
    else
        socat $SOCAT_OPTIONS "$SOCAT_MASTER" "$SOCAT_SLAVE" &
    fi
fi

export ZIGBEE2MQTT_CONFIG_FRONTEND_ENABLED=true
export ZIGBEE2MQTT_CONFIG_FRONTEND_PORT=8099
export ZIGBEE2MQTT_CONFIG_HOMEASSISTANT_ENABLED=true
export Z2M_ONBOARD_URL=http://0.0.0.0:8099
WATCHDOG="$(option '.watchdog')"; [ -z "$WATCHDOG" ] || export Z2M_WATCHDOG="$WATCHDOG"
option_bool '.force_onboarding' && export Z2M_ONBOARD_FORCE_RUN=1 || true

for key in server ca key cert user password base_topic; do
    value="$(option ".mqtt.$key")"
    [ -z "$value" ] || export "ZIGBEE2MQTT_CONFIG_MQTT_$(echo "$key" | tr '[:lower:]' '[:upper:]')=$value"
done
for key in port adapter baudrate rtscts; do
    value="$(option ".serial.$key")"
    [ -z "$value" ] || export "ZIGBEE2MQTT_CONFIG_SERIAL_$(echo "$key" | tr '[:lower:]' '[:upper:]')=$value"
done

# Preserve iHost's MQTT service discovery when the UI has no MQTT server value.
if [ -z "${ZIGBEE2MQTT_CONFIG_MQTT_SERVER:-}" ] && [ -n "${SUPERVISOR_TOKEN:-}" ]; then
    MQTT_SERVICE="$(curl -fsS -H "Authorization: Bearer $SUPERVISOR_TOKEN" "${SUPERVISOR:-http://supervisor}/services/mqtt" 2>/dev/null || true)"
    MQTT_HOST="$(printf '%s' "$MQTT_SERVICE" | jq -r '.data.host // empty' 2>/dev/null || true)"
    MQTT_PORT="$(printf '%s' "$MQTT_SERVICE" | jq -r '.data.port // empty' 2>/dev/null || true)"
    if [ -n "$MQTT_HOST" ] && [ -n "$MQTT_PORT" ]; then
        MQTT_SSL="$(printf '%s' "$MQTT_SERVICE" | jq -r '.data.ssl // false')"
        [ "$MQTT_SSL" = true ] && MQTT_SCHEME=mqtts || MQTT_SCHEME=mqtt
        export ZIGBEE2MQTT_CONFIG_MQTT_SERVER="$MQTT_SCHEME://$MQTT_HOST:$MQTT_PORT"
        export ZIGBEE2MQTT_CONFIG_MQTT_USER="$(printf '%s' "$MQTT_SERVICE" | jq -r '.data.username // empty')"
        export ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD="$(printf '%s' "$MQTT_SERVICE" | jq -r '.data.password // empty')"
    fi
fi

cd /app
exec node index.js
