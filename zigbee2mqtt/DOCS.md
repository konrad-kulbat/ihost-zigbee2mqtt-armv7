# Zigbee2MQTT (iHost ARMv7) documentation

## Configuration

The add-on options are intentionally compatible with the iHost add-on:

- `data_path`: leave at `/config/zigbee2mqtt` to use the existing Zigbee2MQTT
  data directory.
- `serial.port` and `serial.adapter`: copy these exactly from the old add-on.
  The add-on asks Supervisor for UART and udev access; it does not hard-code an
  iHost device path.
- `mqtt`: can be supplied explicitly or inherited from Home Assistant's MQTT
  service.
- `socat`: retains the old TCP-to-PTY bridge option on port 8485.
- `watchdog`: passed to Zigbee2MQTT as `Z2M_WATCHDOG`.

Ingress opens the Zigbee2MQTT frontend on internal port 8099. The Docker health
check requests that local frontend; it is not exposed as a public port by
default.

## First start after migration

Use the existing `data_path` only after the old add-on is stopped. The first
startup must find the prior `configuration.yaml` and `database.db`. Read all
warnings before changing settings. If the log reports a setting that was
removed or renamed, correct the configuration using the Zigbee2MQTT 2.14.1
documentation, retain a backup, and restart. Do not pair devices again merely
because the new frontend initially takes time to populate.

## Updating the wrapper

The add-on wrapper version has the form `<Zigbee2MQTT>-ihost.N`, for example
`2.14.1-ihost.1`. Increment `ihost.N` only for a wrapper change; change the
first part when updating the upstream Zigbee2MQTT source. This prevents the
repository's unique slug and its wrapper releases from being confused with the
old iHost add-on's `2.6.3-1` releases.
