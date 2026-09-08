#!/usr/bin/env bashio

bashio::log.info "Preparing to start Zigbee2MQTT..."
bashio::config.require 'data_path'

if bashio::config.true 'socat.enabled'; then
    SOCAT_MASTER="$(bashio::config 'socat.master')"
    SOCAT_SLAVE="$(bashio::config 'socat.slave')"
    [ -n "$SOCAT_MASTER" ] || bashio::exit.nok "Socat is enabled but master is empty"
    [ -n "$SOCAT_SLAVE" ] || bashio::exit.nok "Socat is enabled but slave is empty"
    SOCAT_OPTIONS="$(bashio::config 'socat.options')"
    if bashio::config.true 'socat.log'; then
        socat $SOCAT_OPTIONS "$SOCAT_MASTER" "$SOCAT_SLAVE" >> "$(bashio::config 'data_path')/socat.log" 2>&1 &
    else
        socat $SOCAT_OPTIONS "$SOCAT_MASTER" "$SOCAT_SLAVE" &
    fi
fi

export ZIGBEE2MQTT_DATA="$(bashio::config 'data_path')"
mkdir -p "$ZIGBEE2MQTT_DATA" || bashio::exit.nok "Could not create $ZIGBEE2MQTT_DATA"
export NODE_PATH=/app/node_modules
export ZIGBEE2MQTT_CONFIG_FRONTEND_ENABLED=true
export ZIGBEE2MQTT_CONFIG_FRONTEND_PORT=8099
export ZIGBEE2MQTT_CONFIG_HOMEASSISTANT_ENABLED=true
export Z2M_ONBOARD_URL=http://0.0.0.0:8099

if bashio::config.has_value 'watchdog'; then export Z2M_WATCHDOG="$(bashio::config 'watchdog')"; fi
if bashio::config.true 'force_onboarding'; then export Z2M_ONBOARD_FORCE_RUN=1; fi

export_config() {
    local key="$1" subkey
    bashio::config.is_empty "$key" && return
    for subkey in $(bashio::jq "$(bashio::config "$key")" 'keys[]'); do
        export "ZIGBEE2MQTT_CONFIG_$(bashio::string.upper "$key")_$(bashio::string.upper "$subkey")=$(bashio::config "$key.$subkey")"
    done
}
export_config mqtt
export_config serial
export TZ="$(bashio::supervisor.timezone)"

if (bashio::config.is_empty mqtt || ! (bashio::config.has_value mqtt.server || bashio::config.has_value mqtt.user || bashio::config.has_value mqtt.password)) && bashio::var.has_value "$(bashio::services mqtt)"; then
    if bashio::var.true "$(bashio::services mqtt ssl)"; then export ZIGBEE2MQTT_CONFIG_MQTT_SERVER="mqtts://$(bashio::services mqtt host):$(bashio::services mqtt port)"; else export ZIGBEE2MQTT_CONFIG_MQTT_SERVER="mqtt://$(bashio::services mqtt host):$(bashio::services mqtt port)"; fi
    export ZIGBEE2MQTT_CONFIG_MQTT_USER="$(bashio::services mqtt username)"
    export ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD="$(bashio::services mqtt password)"
fi

cd /app
exec node index.js
