# piano-sensors

Sensors for the Xiaomi Pad 8 Pro (piano, Qualcomm SM8750) on Debian trixie: accelerometer (screen rotation), ambient light, proximity and compass, served by the Snapdragon Sensor Core on the ADSP.

Mainline Linux already talks to the sensors hub: the `fastrpc` driver exposes the ADSP, Qualcomm's FastRPC userspace (`adsprpcd`, Debian `fastrpc-support`) serves the sensors protection domain, libssc speaks its QMI protocol and iio-sensor-proxy hands the readings to the desktop. This repository adds what is missing on Debian trixie as packages with a `+piano` version suffix:

- **libssc** is not in trixie; it is rebuilt unchanged from Debian unstable.
- **iio-sensor-proxy** misses a client that claims a sensor while the SSC driver is still opening, so the screen never rotates after boot; it is rebuilt from Debian unstable with a fix.
- **piano-sensors** ties it together for this tablet.

## Contents

| Path | Purpose |
|---|---|
| `patches/iio-sensor-proxy/` | Patch applied to Debian's `iio-sensor-proxy` source package (GPL-2+) |
| `piano-sensors/` | Native `piano-sensors` package: odm and persist import, `adsprpcd-sensorspd` service (ready only once the sensors PD has published every sensor iio-sensor-proxy uses), udev rule with the accelerometer mount matrix, systemd drop-in, APT pin |
| `scripts/build-sensors-debs.sh` | Builds everything inside a Debian trixie arm64 system; writes `all/`, `runtime/` and `SHA256SUMS` |
| `scripts/build-in-container.sh` | Runs the build in a clean `debian:trixie` container on an arm64 host |
| `.github/workflows/build.yml` | CI: shellcheck, then the build on an arm64 runner |

The source packages come from Debian unstable (libssc 0.4.4-2, iio-sensor-proxy 3.9-1) and are rebuilt for trixie; each `.dsc` is checked against a pinned SHA-256. The FastRPC packages (`fastrpc-support`, `libfastrpc1` 1.0.7 from trixie-backports contrib) are used as Debian built them, with pinned checksums.

`fastrpc-support` starts every remote processor and its root and audio PD daemons from udev. On piano the ADSP is started by the image's own service and audio streams are not safe yet, so `piano-sensors` overrides that udev rule and masks those two daemons; only the sensors PD is served.

## Device data

The sensors PD needs files that belong to each tablet: the JSON sensor configuration on the odm partition (`/odm/etc/sensors/config/json.lst` and the files it lists), and the registry and calibration on persist (`/mnt/vendor/persist/sensors`). After every ADSP start the PD reads `json.lst` first and gives up without it, even when the registry on persist is valid. None of these files are shipped. On first boot `piano-sensors-import` copies them into `/var/lib/piano-sensors` and links the two paths the PD asks for to the copies:

- odm_a (EROFS) is a logical partition inside `super`: it is mapped read-only with device-mapper from the super metadata and read with `dump.erofs`, never mounted;
- persist (ext4) is mounted read-only with `noload`, so it is never written; the ADSP updates its registry in the copy.

Delete `/var/lib/piano-sensors/odm/config` or `/var/lib/piano-sensors/persist/sensors` to import that part again.

## Build

On an arm64 host with Docker:

```sh
scripts/build-in-container.sh out/sensors
```

Inside a Debian trixie arm64 system, as root: `scripts/build-sensors-debs.sh out/sensors`.

## Consumers

The debian-piano image build checks out this repository's `main` branch, builds it with `scripts/build-in-container.sh` and installs the runtime packages into the rootfs. `piano-sensors` pins the `+piano` versions, so an `apt upgrade` from Debian cannot replace them with stock packages. The packages are ordinary versioned Debian packages, so they can be served from an APT repository for updates.

## Updating

- New Debian version of a source package: change its version and `.dsc` checksum in `scripts/build-sensors-debs.sh`, rebuild, and check that the patches still apply.
- Integration changes: edit `piano-sensors/` and add a `debian/changelog` entry, so the version rises and updates reach installed systems.
- A patch lands upstream and reaches Debian: drop it. When no patch is left, only the `piano-sensors` package remains.
