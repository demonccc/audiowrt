#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Storage is optional and must not be inherited by any mandatory or selectable
# package group. It may exist as an AudioWRT-owned package and build target, but
# firmware profiles opt into it explicitly when needed.
if grep -R -Eq '^  - (audiowrt-storage|audiowrt-storage-luci)$' "$repo_root/config/package-groups"/*.yaml; then
    echo "ERROR: storage packages must not be part of the mandatory AudioWRT package-group baseline." >&2
    exit 1
fi

grep -q '^audiowrt-storage-luci|package/feeds/audiowrt/luci-app-audiowrt-storage/compile$' \
    "$repo_root/config/build/package-build-targets"

# AudioWRT requires /var to remain volatile runtime storage.
grep -Fq 'CONFIG_TARGET_ROOTFS_PERSIST_VAR=y' "$repo_root/scripts/build.sh"
grep -Fq 'AudioWRT requires volatile /var' "$repo_root/scripts/build.sh"

echo 'Storage baseline tests passed.'
