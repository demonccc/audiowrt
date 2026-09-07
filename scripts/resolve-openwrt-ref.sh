#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

requested_release="${1:-stable}"
openwrt_repo="${OPENWRT_REPOSITORY:-https://github.com/openwrt/openwrt.git}"

if [[ "$requested_release" == "stable" ]]; then
    latest_tag="$({
        git ls-remote --tags --refs "$openwrt_repo" 'refs/tags/v*' \
            | awk '{ sub("refs/tags/", "", $2); print $2 }' \
            | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
            | sort -V \
            | tail -n 1
    } || true)"

    if [[ -z "$latest_tag" ]]; then
        echo "ERROR: unable to resolve the latest stable OpenWrt release tag." >&2
        exit 2
    fi

    printf '%s\n' "$latest_tag"
    exit 0
fi

case "$requested_release" in
    v[0-9]*.[0-9]*.[0-9]*) normalized="$requested_release" ;;
    [0-9]*.[0-9]*.[0-9]*) normalized="v${requested_release}" ;;
    *)
        echo "ERROR: AudioWRT requires an exact final OpenWrt release such as 25.12.5 or v25.12.5." >&2
        echo "Branches such as openwrt-25.12, main, snapshots and release candidates are not accepted." >&2
        exit 3
        ;;
esac

if ! [[ "$normalized" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: invalid OpenWrt release: $requested_release" >&2
    exit 3
fi

printf '%s\n' "$normalized"
