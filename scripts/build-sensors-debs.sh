#!/usr/bin/env bash
# build-sensors-debs.sh — build the piano sensors stack as Debian packages.
#
# Usage (as root, in a Debian trixie arm64 system or container):
#   scripts/build-sensors-debs.sh OUTPUT_DIR
#
# Rebuilds two Debian unstable source packages for trixie with a "+piano"
# version suffix, in dependency order:
#   libssc            unchanged (not in trixie; iio-sensor-proxy needs it)
#   iio-sensor-proxy  + patches/iio-sensor-proxy/*.patch
# adds Qualcomm's FastRPC userspace (adsprpcd) unchanged from trixie-backports
# contrib, and builds the native piano-sensors package from piano-sensors/.
#
# Output:
#   OUTPUT_DIR/all/      every binary package of the build
#   OUTPUT_DIR/runtime/  what the image installs (no -dev, debug symbols,
#                        tests or introspection data)
#   OUTPUT_DIR/SHA256SUMS
set -euo pipefail

OUTPUT=${1:?usage: build-sensors-debs.sh OUTPUT_DIR}
REPO=$(cd "$(dirname "$0")/.." && pwd)
BUILD_ROOT=/build/sensors
# Source versions from Debian unstable, with the SHA-256 of each .dsc; the
# .dsc in turn pins the tarballs. snapshot.debian.org keeps them after
# unstable moves on.
SOURCES=(
    'libssc 0.4.4-2 libs/libssc'
    'iio-sensor-proxy 3.9-1 i/iio-sensor-proxy'
)
declare -A DSC_SHA256=(
    [libssc]=3f79e8cad936a647f2c7773c5fb2fa4fdd3a96d893f70279aa3e7a9b55023fef
    [iio-sensor-proxy]=92fa4df9f49c8c1596dad44b44212ba30f4958acf86327dec215548ffaa716bd
)
MIRROR=${DEBIAN_MIRROR:-https://deb.debian.org/debian}
SNAPSHOT=https://snapshot.debian.org/archive/debian/20260929T000000Z

die() { echo "build-sensors-debs: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die 'run as root'
[ "$(dpkg --print-architecture)" = arm64 ] || die 'arm64 only'
mkdir -p "$OUTPUT"
OUTPUT=$(realpath "$OUTPUT")

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential ca-certificates curl devscripts dpkg-dev equivs

fetch() {
    local name=$1 version=$2 dir=$3 file base
    base="${name}_${version}"
    for url in "$MIRROR/pool/main/$dir" "$SNAPSHOT/pool/main/$dir"; do
        if curl -fsSLO "$url/$base.dsc"; then
            echo "${DSC_SHA256[$name]}  $base.dsc" | sha256sum -c - || die "$base.dsc checksum mismatch"
            while read -r file; do
                curl -fsSLO "$url/$file" || continue 2
            done < <(awk '/^Files:/{f=1;next} /^[^ ]/{f=0} f && NF == 3 {print $3}' "$base.dsc")
            dpkg-source -x "$base.dsc" "$name"
            return
        fi
    done
    die "cannot download $base"
}

build() {
    local name=$1 message=$2 patch
    cd "$BUILD_ROOT/$name"
    mkdir -p debian/patches
    for patch in "$REPO/patches/$name"/*.patch; do
        [ -e "$patch" ] || continue
        cp "$patch" debian/patches/
        basename "$patch" >> debian/patches/series
    done
    DEBFULLNAME='piano mainline contributors' DEBEMAIL='piano@localhost' \
        dch --local +piano --distribution trixie "$message"
    mk-build-deps -i -r -t 'apt-get -y --no-install-recommends' debian/control
    DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" DEB_BUILD_PROFILES=nocheck \
        dpkg-buildpackage -b -uc -us
    cp ../*.deb "$OUTPUT/all/"
    rm -f ../*.deb ../*.buildinfo ../*.changes
}

rm -rf "$BUILD_ROOT" "$OUTPUT/all" "$OUTPUT/runtime"
mkdir -p "$BUILD_ROOT" "$OUTPUT/all" "$OUTPUT/runtime"
cd "$BUILD_ROOT"
for entry in "${SOURCES[@]}"; do
    read -r name version dir <<< "$entry"
    fetch "$name" "$version" "$dir"
done

build libssc 'Rebuild for trixie (needed by iio-sensor-proxy SSC support).'
# iio-sensor-proxy build-depends on the libssc just built.
apt-get install -y --no-install-recommends "$OUTPUT"/all/libssc-dev_*.deb \
    "$OUTPUT"/all/libssc2_*.deb "$OUTPUT"/all/gir1.2-ssc-2_*.deb
build iio-sensor-proxy 'Start polling for clients that claim SSC sensors during driver open.'

# adsprpcd serves the sensors PD; taken as built by Debian, checksums pinned.
FASTRPC_POOL=$MIRROR/pool/contrib/f/fastrpc
FASTRPC_DEBS=(
    '3beabcb39acdb0f8e6982ea6245d256b2b4cd657198f9161326c986e20e43442 fastrpc-support_1.0.7-2~bpo13+1_arm64.deb'
    '35df085e1abb15abfba103c9947d86a686fb530c3d383a7f5e10834d51a1df26 libfastrpc1_1.0.7-2~bpo13+1_arm64.deb'
)
for entry in "${FASTRPC_DEBS[@]}"; do
    read -r sum deb <<< "$entry"
    curl -fsSL -o "$OUTPUT/all/$deb" "$FASTRPC_POOL/$deb" || die "cannot download $deb"
    echo "$sum  $OUTPUT/all/$deb" | sha256sum -c - || die "$deb checksum mismatch"
done

cp -r "$REPO/piano-sensors" "$BUILD_ROOT/piano-sensors"
cd "$BUILD_ROOT/piano-sensors"
mk-build-deps -i -r -t 'apt-get -y --no-install-recommends' debian/control
dpkg-buildpackage -b -uc -us
cp ../*.deb "$OUTPUT/all/"

for deb in "$OUTPUT"/all/*.deb; do
    case $(dpkg-deb -f "$deb" Package) in
        *-dev | *-dbgsym | *-dbg | *-tests | gir1.2-*) ;;
        *) cp "$deb" "$OUTPUT/runtime/" ;;
    esac
done
for pkg in fastrpc-support libfastrpc1 iio-sensor-proxy libssc2 piano-sensors; do
    grep -q . <(find "$OUTPUT/runtime" -name "${pkg}_*.deb") || die "no $pkg package was built"
done
(cd "$OUTPUT" && find . -name '*.deb' | sort | xargs sha256sum > SHA256SUMS)
echo "build-sensors-debs: $(find "$OUTPUT/runtime" -name '*.deb' | wc -l) runtime packages in $OUTPUT"
