#!/usr/bin/env bash
# build-in-container.sh — run build-sensors-debs.sh in a clean debian:trixie
# container on an arm64 host (CI runner or workstation) with Docker. Files
# the container creates are handed back to the calling user afterwards.
#
# Usage:
#   scripts/build-in-container.sh OUTPUT_DIR
set -euo pipefail

OUTPUT=${1:?usage: build-in-container.sh OUTPUT_DIR}
REPO=$(cd "$(dirname "$0")/.." && pwd)

mkdir -p "$OUTPUT"
OUTPUT=$(realpath "$OUTPUT")

status=0
docker run --rm -v "$REPO:/src:ro" -v "$OUTPUT:/out" \
    debian:trixie /src/scripts/build-sensors-debs.sh /out || status=$?
docker run --rm -v "$OUTPUT:/out" debian:trixie chown -R "$(id -u):$(id -g)" /out
exit "$status"
