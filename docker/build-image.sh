#!/usr/bin/env bash
#
# Build the GRiSP Alloy builder docker image. Used by the build-*.sh scripts
# when invoked with -D and the image is missing, and can be run manually to
# rebuild the image (pass --no-cache for a clean rebuild).

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
IMAGE_NAME="${GRISP_ALLOY_DOCKER_IMAGE:-grisp-alloy-builder:latest}"

if ! command -v docker > /dev/null 2>&1; then
    echo "ERROR: docker not found in PATH" 1>&2
    exit 1
fi

echo "Building ${IMAGE_NAME}..."
docker build "$@" -t "$IMAGE_NAME" "$SCRIPT_DIR"
