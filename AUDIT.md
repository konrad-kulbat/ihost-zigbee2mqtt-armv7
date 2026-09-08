# Audit and implementation record — 2026-09-08

## Evidence examined

- iHost `hassio-ihost-zigbee2mqtt/config.json` at current `master`: version
  `2.6.3-1`, only `armv7`, image
  `ghcr.io/ihost-open-source-project/hassio-ihost-zigbee2mqtt-{arch}`.
- Its directory contains only manifest, documentation and artwork: no Dockerfile,
  runtime script, build script or workflow. Its history for `config.json` has a
  single adding commit (`5f25b326`, 2025-12-22).
- Official `hassio-zigbee2mqtt` at current `master`: version `2.14.1-1`,
  `aarch64` and `amd64`, and image
  `ghcr.io/zigbee2mqtt/zigbee2mqtt-{arch}`. It contains a common Dockerfile,
  `build.yaml`, `rootfs/docker-entrypoint.sh` and CI that copies those common
  files before a Home Assistant Builder build.
- Upstream Zigbee2MQTT release `2.14.1` is the current stable release examined.
  Its `package.json` requires Node `^22.2.0 || ^24 || <=26.2`; native build
  allowlist includes `@serialport/bindings-cpp`, `esbuild` and `unix-dgram`.

Sources: [iHost manifest](https://raw.githubusercontent.com/iHost-Open-Source-Project/hassio-ihost-addon/master/hassio-ihost-zigbee2mqtt/config.json), [official manifest](https://raw.githubusercontent.com/zigbee2mqtt/hassio-zigbee2mqtt/master/zigbee2mqtt/config.json), [official Dockerfile](https://raw.githubusercontent.com/zigbee2mqtt/hassio-zigbee2mqtt/master/common/Dockerfile), [upstream package metadata](https://raw.githubusercontent.com/Koenkk/zigbee2mqtt/2.14.1/package.json), and [2.0.0 release notes](https://github.com/Koenkk/zigbee2mqtt/releases/tag/2.0.0).

## Comparison and decision

| Area | iHost | Official add-on | This repository |
| --- | --- | --- | --- |
| Runtime version | 2.6.3 | 2.14.1 | 2.14.1 |
| Architectures | ARMv7 only | amd64/aarch64 only | ARMv7 only |
| Data default | `/config/zigbee2mqtt` | same | unchanged |
| Ingress, MQTT service, UART/udev, socat, watchdog | present | present | retained |
| Image | old iHost GHCR image | official per-arch GHCR image | separate owner GHCR image |

The iHost-specific part is the ARMv7 target and the legacy iHost deployment
context—not a separate runtime implementation. The official HA base-image
project now supports only amd64/arm64, so `ghcr.io/home-assistant/armv7-base:3.24`
does not exist. This was confirmed by the failed CI run and by Home Assistant's
current base-image support statement. It makes the previously selected HA-base
build route invalid.

The replacement is a dedicated, minimal add-on wrapper over the official pinned
`ghcr.io/koenkk/zigbee2mqtt:2.14.1` image. Zigbee2MQTT documents that its image
supports `linux/arm/v7`. The wrapper maps `/data/options.json` into the same
Zigbee2MQTT environment variables used by the official add-on and retains MQTT
service discovery through the Supervisor API. Its Dockerfile verifies Node 22+
while building; the upstream image carries the ARMv7-native serial binding.

## Upgrade risk: 2.6.3 → 2.14.1

This upgrade is already within the 2.x series; it does **not** cross the 2.0.0
boundary. That release is nevertheless relevant for rollback history and for an
installation whose data directory was first created on 1.x. Zigbee2MQTT 2.0.0
requires Home Assistant 2024.9 or newer, removes legacy APIs/settings, changes the default
`homeassistant.status_topic` to `homeassistant/status`, changes permit-join
behaviour, reworks OTA, removes `permit_join_timeout` and configuration-driven
group members, and migrates settings automatically. MQTT consumers and custom
automations must be reviewed for removed legacy topics/entities. The release
notes explicitly say a downgrade to 1.x requires restoring the old backed-up
`configuration.yaml`; the same conservative restoration is prescribed here.

There is no evidence in this audit that network keys, `database.db`, or
coordinator state require intentional recreation. Compatibility is **REVIEW**,
not PASS, until the actual existing data directory and first 2.14.1 migration
log are inspected on the device.

## Scope deliberately not claimed

No physical iHost, coordinator, MQTT broker, Docker daemon, or GitHub package
credentials are available in this workspace. Consequently no ARMv7 image has
yet been built/published and no serial/MQTT/ingress runtime test has been
claimed. The workflow is designed to supply those checks after the owner
placeholder is configured.
