#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
builder_image="${BUILDER_IMAGE:-demonccc/openwrt-builder:latest}"
log_file="${LOG_FILE:-}"
cache_dir="${CACHE_DIR:-}"
container_cache_dir=""

if [[ -n "$log_file" ]]; then
    if [[ "$log_file" = /* ]]; then
        requested_log_path="$log_file"
    else
        requested_log_path="$repo_root/$log_file"
    fi

    mkdir -p "$(dirname "$requested_log_path")"
    log_dir="$(cd "$(dirname "$requested_log_path")" && pwd -P)"
    log_path="$log_dir/$(basename "$requested_log_path")"
    work_root="$repo_root/.work"
    output_root="$repo_root/output"

    case "$log_path" in
        "$work_root"|"$work_root"/*|"$output_root"|"$output_root"/*)
            echo "ERROR: LOG_FILE must be outside .work/ and output/ because those directories are recreated by the build." >&2
            exit 2
            ;;
    esac

    echo "Logging build output to: $log_path"
    exec > >(tee "$log_path") 2>&1
fi

if [[ -n "$cache_dir" ]]; then
    if [[ "$cache_dir" = /* ]]; then
        requested_cache_path="$cache_dir"
    else
        requested_cache_path="$repo_root/$cache_dir"
    fi

    mkdir -p "$requested_cache_path"
    cache_path="$(cd "$requested_cache_path" && pwd -P)"

    case "$cache_path" in
        "$repo_root"/.work|"$repo_root"/.work/*|"$repo_root"/output|"$repo_root"/output/*)
            echo "ERROR: CACHE_DIR must be outside .work/ and output/ because those directories are recreated by the build." >&2
            exit 2
            ;;
        "$repo_root"/*)
            container_cache_dir="/workspace/${cache_path#"$repo_root"/}"
            ;;
        *)
            echo "ERROR: CACHE_DIR must be inside the AudioWRT checkout so it is available inside Docker." >&2
            exit 2
            ;;
    esac

    echo "Using persistent local download cache: $cache_path"
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
    -e CACHE_DIR="$container_cache_dir" \
    -v "$repo_root:/workspace" \
    -w /workspace \
    "$builder_image" \
    bash scripts/build.sh
