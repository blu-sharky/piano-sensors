# piano-sensors

Sensors for the Xiaomi Pad 8 Pro (piano, Qualcomm SM8750) on Debian trixie: accelerometer (screen rotation), ambient light, proximity and compass, served by the Snapdragon Sensor Core on the ADSP.

Mainline Linux already talks to the sensors hub: the `fastrpc` driver exposes the ADSP, libssc speaks its QMI protocol and iio-sensor-proxy hands the readings to the desktop. Two things are missing on this SoC, and this repository adds them as Debian packages with a `+piano` version suffix:

- **hexagonrpcd** has to serve the sensors protection domain of the ADSP firmware. The SM8750 firmware reads its configuration from `/odm`, writes its registry back to persist, calls extended `apps_std` methods and passes large arguments; stock hexagonrpcd supports none of this and stops.
- **iio-sensor-proxy** misses a client that claims a sensor while the SSC driver is still opening, so the screen never rotates after boot.

## Contents

| Path | Purpose |
|---|---|
| `patches/hexagonrpc/` | Patch applied to Debian's `hexagonrpc` source package (GPL-3+) |
| `patches/iio-sensor-proxy/` | Patch applied to Debian's `iio-sensor-proxy` source package (GPL-2+) |
| `piano-sensors/` | Native `piano-sensors` package: data import, udev rule with the accelerometer mount matrix, systemd drop-ins, APT pin |
| `scripts/build-sensors-debs.sh` | Builds everything inside a Debian trixie arm64 system; writes `all/`, `runtime/` and `SHA256SUMS` |
| `scripts/build-in-container.sh` | Runs the build in a clean `debian:trixie` container on an arm64 host |
| `.github/workflows/build.yml` | CI: shellcheck, then the build on an arm64 runner |

The source packages come from Debian unstable (libssc 0.4.4-2, iio-sensor-proxy 3.9-1, hexagonrpc 0.4.0-2) and are rebuilt for trixie. Each `.dsc` is checked against a pinned SHA-256; libssc is rebuilt unchanged because trixie lacks it.

## Device data

The sensors PD needs files that belong to each tablet: the JSON sensor configuration on the odm partition, and the calibration and registry on persist. None of them are shipped. On first boot `piano-sensors-import` copies them into `/var/lib/piano-sensors`:

- odm_a (EROFS) is a logical partition inside `super`: it is mapped read-only with device-mapper from the super metadata and read with `dump.erofs`, never mounted;
- persist (ext4) is mounted read-only with `noload`, so it is never written; the ADSP writes its registry into the copy.

Delete `/var/lib/piano-sensors/sensors/config` or `/var/lib/piano-sensors/persist/sensors` to import that part again.

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
