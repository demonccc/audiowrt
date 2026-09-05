#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

requested_ref="${1:-stable}"
openwrt_repo="${OPENWRT_REPOSITORY:-https://github.com/openwrt/openwrt.git}"

if [[ "$requested_ref" != "stable" ]]; then
    printf '%s\n' "$requested_ref"
    exit 0
fi

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
