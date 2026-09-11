#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if grep -Eq '^[[:space:]]*(audiowrt-storage|audiowrt-storage-luci)[[:space:]]*$' "$repo_root/config/packages.add"; then
    echo "ERROR: storage packages must not be part of the mandatory AudioWRT baseline." >&2
    exit 1
fi

if grep -Eq '^[[:space:]]*DEPENDS:=.*audiowrt-storage' "$repo_root/package/luci-app-audiowrt-core/Makefile"; then
    echo "ERROR: luci-app-audiowrt-core must not depend on storage." >&2
    exit 1
fi

grep -q '^storage|audiowrt-storage-luci|' "$repo_root/config/features.map"
grep -q '^audiowrt-storage-luci|package/audiowrt/luci-app-audiowrt-storage/compile$' "$repo_root/config/package-build-targets"
grep -q 'DEPENDS:=.*+audiowrt-storage' "$repo_root/package/luci-app-audiowrt-storage/Makefile"

echo 'Storage baseline tests passed.'
