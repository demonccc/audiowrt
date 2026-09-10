#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

core_config="$repo_root/package/audiowrt-core/files/audiowrt.config"
provisioning="$repo_root/package/audiowrt-provisioning"
storage="$repo_root/package/audiowrt-storage/files/audiowrt-storage"
menu_filter="$repo_root/package/luci-app-audiowrt-core/root/usr/share/luci/menu.d/zz-audiowrt-network-filter.json"

# Canonical OpenWrt state must not be duplicated in /etc/config/audiowrt.
if grep -Eq 'device_name|wifi_ssid|^config storage' "$core_config"; then
    echo 'ERROR: AudioWRT core config duplicates hostname, Wi-Fi, or storage state.' >&2
    exit 1
fi
grep -q 'system.@system\[0\].hostname' "$repo_root/package/audiowrt-core/files/audiowrt-core-firstboot"

# Provisioning delegates network capability to the reusable package.
grep -q '+audiowrt-wifi-client' "$provisioning/Makefile"
grep -q '/usr/sbin/audiowrt-wifi-client' "$provisioning/files/audiowrt-provisioning-firstboot"
grep -q '/usr/sbin/audiowrt-wifi-client connect' "$provisioning/files/audiowrt-provision"
grep -q '/bin/busybox passwd root' "$provisioning/files/audiowrt-provision.cgi"
grep -q 'audiowrt-scan.cgi' "$provisioning/Makefile"
grep -q 'audiowrt-radios.cgi' "$provisioning/Makefile"

# The first-boot UI is the six-step flow and supports password visibility.
for label in 'Welcome' 'Select Wi-Fi' 'Wi-Fi password' 'Administrator password' 'Connect' 'Done'; do
    grep -q "$label" "$provisioning/files/audiowrt.html"
done
grep -q 'data-target="key"' "$provisioning/files/audiowrt.html"
grep -q 'data-target="admin_password"' "$provisioning/files/audiowrt.html"

# Storage owns its own UCI namespace.
grep -q 'audiowrt-storage.main' "$storage"
if grep -q 'audiowrt\.storage' "$storage"; then
    echo 'ERROR: storage runtime still writes the legacy audiowrt.storage section.' >&2
    exit 1
fi

# AudioWRT reuses selected native LuCI modules while keeping router-only pages hidden.
for package in luci-mod-status luci-mod-system luci-mod-network luci-app-package-manager; do
    grep -qx "$package" "$repo_root/config/packages.add"
    if grep -qx "$package" "$repo_root/config/packages.remove"; then
        echo "ERROR: $package is both added and removed." >&2
        exit 1
    fi
done
if grep -q 'admin/network/diagnostics' "$menu_filter"; then
    echo 'ERROR: Diagnostics must remain visible; it should not be overridden by the hidden-menu file.' >&2
    exit 1
fi
grep -q 'admin/network/wireless' "$menu_filter"

# Reusable Wi-Fi packages must be part of the SDK-owned build map.
grep -q '^audiowrt-wifi-client|' "$repo_root/config/package-build-targets"
grep -q '^luci-app-audiowrt-wifi-client|' "$repo_root/config/package-build-targets"

# Duplicate AudioWRT Network/System views are intentionally gone.
[ ! -e "$repo_root/package/luci-app-audiowrt-core/htdocs/luci-static/resources/view/audiowrt-core/network.js" ]
[ ! -e "$repo_root/package/luci-app-audiowrt-core/htdocs/luci-static/resources/view/audiowrt-core/system.js" ]

echo 'AudioWRT appliance integration tests passed.'
