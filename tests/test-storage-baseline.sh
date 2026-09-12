#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if grep -Eq '^[[:space:]]*(audiowrt-storage|audiowrt-storage-luci)[[:space:]]*$' "$repo_root/config/flavors/minimal/packages.add"; then
    echo "ERROR: storage packages must not be part of the mandatory AudioWRT baseline." >&2
    exit 1
fi

grep -q '^audiowrt-storage-luci|package/feeds/audiowrt/luci-app-audiowrt-storage/compile$' "$repo_root/config/package-build-targets"
grep -qx 'audiowrt-storage-luci' "$repo_root/config/flavors/standard/packages.add"
grep -qx 'audiowrt-storage-luci' "$repo_root/config/flavors/full/packages.add"

echo 'Storage baseline tests passed.'
