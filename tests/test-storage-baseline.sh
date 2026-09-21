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

grep -q '^audiowrt-storage-luci|package/feeds/audiowrt/luci-app-audiowrt-storage/compileecho 'Storage baseline tests passed.'
 \
    "$repo_root/config/build/package-build-targets"

# /var is runtime storage in AudioWRT. Reject ImageBuilders that would make
# it persistent, otherwise upstream daemons could turn ordinary state/cache
# updates into internal-flash writes.
grep -Fq "CONFIG_TARGET_ROOTFS_PERSIST_VAR=y" "$repo_root/scripts/build.sh"
grep -Fq "AudioWRT requires volatile /var" "$repo_root/scripts/build.sh"

echo 'Storage baseline tests passed.'
