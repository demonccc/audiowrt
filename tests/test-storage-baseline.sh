#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Storage is optional and must not be inherited by any base flavor fragment or selectable flavor.
if grep -R -Eq '^  - (audiowrt-storage|audiowrt-storage-luci)$' "$repo_root/config/flavors"/*.yaml; then
    echo "ERROR: storage packages must not be part of the mandatory AudioWRT flavor baseline." >&2
    exit 1
fi

grep -q '^audiowrt-storage-luci|package/feeds/audiowrt/luci-app-audiowrt-storage/compile$' "$repo_root/config/package-build-targets"

echo 'Storage baseline tests passed.'
