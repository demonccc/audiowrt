#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages="$repo_root/config/packages.add"

# Keep the general LuCI pages explicitly requested for the appliance, while
# AudioWRT owns network setup through its dedicated Wi-Fi/IP configuration UI.
for required in \
    luci-base \
    luci-theme-bootstrap \
    luci-mod-status \
    luci-mod-system \
    luci-app-package-manager \
    luci-app-audiowrt \
    luci-app-audiowrt-wifi-client \
    luci-app-audiowrt-core; do
    grep -qx "$required" "$packages"
done

if grep -qx 'luci-mod-network' "$packages"; then
    echo 'ERROR: luci-mod-network must not be preinstalled; AudioWRT owns network configuration.' >&2
    exit 1
fi

echo 'AudioWRT LuCI network ownership tests passed.'
