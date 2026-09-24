#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolved="$(python3 "$repo_root/scripts/resolve-audiowrt-profile.py" \
    "$repo_root/profiles" \
    "$repo_root/config/package-groups" \
    tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5)"

python3 -c '
import json, sys
data = json.load(sys.stdin)
packages = set(data["packages_add"])
removed = set(data["packages_remove"])
required = {
    "luci-base",
    "luci-theme-bootstrap",
    "luci-mod-status",
    "luci-mod-system",
    "luci-app-package-manager",
    "audiowrt-network-client",
    "audiowrt-wifi-client",
    "luci-app-audiowrt",
    "luci-app-audiowrt-network-client",
    "luci-app-audiowrt-core",
    "luci-app-audiowrt-renderer",
}
assert required <= packages
for package in {
    "luci",
    "luci-light",
    "luci-mod-admin-full",
    "luci-mod-network",
    "luci-app-firewall",
    "luci-proto-ppp",
}:
    assert package not in packages
    assert package in removed
' <<< "$resolved"

echo 'AudioWRT LuCI network ownership tests passed.'
