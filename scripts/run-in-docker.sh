#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
builder_image="${BUILDER_IMAGE:-demonccc/openwrt-builder:latest}"
log_file="${LOG_FILE:-}"

if [[ -n "$log_file" ]]; then
    if [[ "$log_file" = /* ]]; then
        log_path="$(realpath -m "$log_file")"
    else
        log_path="$(realpath -m "$repo_root/$log_file")"
    fi

    work_root="$(realpath -m "$repo_root/.work")"
    output_root="$(realpath -m "$repo_root/output")"

    case "$log_path" in
        "$work_root"|"$work_root"/*|"$output_root"|"$output_root"/*)
            echo "ERROR: LOG_FILE must be outside .work/ and output/ because those directories are recreated by the build." >&2
            exit 2
            ;;
    esac

    mkdir -p "$(dirname "$log_path")"
    echo "Logging build output to: $log_path"
    exec > >(tee "$log_path") 2>&1
fi

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: Docker is required to build AudioWRT." >&2
    exit 2
}

if ! docker pull "$builder_image"; then
    echo "ERROR: unable to pull the configured OpenWrt builder image: $builder_image" >&2
    echo "AudioWRT does not build its own Docker image. Publish/fix the image in demonccc/openwrt-builder or select another compatible BUILDER_IMAGE." >&2
    exit 3
fi

uid="$(id -u)"
gid="$(id -g)"

docker run --rm \
    --user "$uid:$gid" \
    -e HOME=/tmp \
    -e AUDIOWRT_IN_CONTAINER=1 \
    -e BUILDER_IMAGE="$builder_image" \
    -e PLATFORM="${PLATFORM:-}" \
    -e OPENWRT_RELEASE="${OPENWRT_RELEASE:-25.12.5}" \
    -e OPENWRT_REPOSITORY="${OPENWRT_REPOSITORY:-https://github.com/openwrt/openwrt.git}" \
    -e AUDIOWRT_PACKAGES_REPOSITORY="${AUDIOWRT_PACKAGES_REPOSITORY:-https://github.com/demonccc/audiowrt-packages.git}" \
    -e AUDIOWRT_PACKAGES_REF="${AUDIOWRT_PACKAGES_REF:-main}" \
    -e FEATURES="${FEATURES:-}" \
    -e JOBS="${JOBS:-}" \
    -e VERBOSITY="${VERBOSITY:-normal}" \
    -v "$repo_root:/workspace" \
    -w /workspace \
    "$builder_image" \
    bash scripts/build.sh
