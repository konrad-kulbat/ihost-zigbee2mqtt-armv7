# Changelog

# 2.14.1-ihost.2

- Replace the unavailable Home Assistant ARMv7 base image with the official
  Zigbee2MQTT ARMv7 image as the wrapper base.

## 2.14.1-ihost.1

- Initial ARMv7-only iHost-compatible add-on.
- Zigbee2MQTT: 2.14.1.
- Preserves the iHost default data path `/config/zigbee2mqtt`, ingress, serial/udev access, socat, MQTT service discovery and watchdog environment variable.
- Uses the official ARMv7 Zigbee2MQTT image, because Home Assistant no longer publishes an ARMv7 base image.
