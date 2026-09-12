#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for flavor in minimal standard full; do
    add="$repo_root/config/flavors/$flavor/packages.add"
    remove="$repo_root/config/flavors/$flavor/packages.remove"
    test -s "$add"
    test -s "$remove"
    if comm -12 <(grep -Ev '^[[:space:]]*(#|$)' "$add" | sort -u) \
        <(grep -Ev '^[[:space:]]*(#|$)' "$remove" | sort -u) | grep -q .; then
        echo "ERROR: $flavor adds and removes the same package." >&2
        exit 1
    fi
done

minimal_add="$repo_root/config/flavors/minimal/packages.add"
minimal_remove="$repo_root/config/flavors/minimal/packages.remove"
for package in audiowrt-minimal-alsa audiowrt-minimal-mbedtls kmod-audiowrt-bluetooth; do
    grep -qx "$package" "$minimal_add"
done
for package in alsa-lib libmbedtls21 kmod-bluetooth kmod-btusb kmod-btmtk odhcp6c; do
    grep -qx "$package" "$minimal_remove"
done

for flavor in standard full; do
    add="$repo_root/config/flavors/$flavor/packages.add"
    remove="$repo_root/config/flavors/$flavor/packages.remove"
    for package in alsa-lib libmbedtls21 kmod-bluetooth kmod-btusb; do
        grep -qx "$package" "$add"
    done
    for package in audiowrt-minimal-alsa audiowrt-minimal-mbedtls kmod-audiowrt-bluetooth; do
        grep -qx "$package" "$remove"
    done
done

grep -qx 'audiowrt-mpd' "$repo_root/config/flavors/standard/packages.add"
for package in audiowrt-mpd audiowrt-airplay audiowrt-spotify audiowrt-storage-luci; do
    grep -qx "$package" "$repo_root/config/flavors/full/packages.add"
done

for profile_file in "$repo_root"/profiles/*.yaml; do
    profile="$(basename "$profile_file" .yaml)"
    resolved="$(python3 "$repo_root/scripts/resolve-audiowrt-profile.py" \
        "$repo_root/profiles" "$repo_root/config/flavors" "$profile")"
    python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["id"] == sys.argv[1]
assert data["flavor"] in {"minimal", "standard", "full"}
assert data["openwrt_source"] in {"release", "snapshot"}
assert data["id"].endswith("-" + data["openwrt_version"])
assert data["maintainer_github"]
assert data["target"] and data["subtarget"] and data["openwrt_profile"]
assert not set(data["packages_add"]) & set(data["packages_remove"])
' "$profile" <<< "$resolved"
done

wdr="$(python3 "$repo_root/scripts/resolve-audiowrt-profile.py" \
    "$repo_root/profiles" "$repo_root/config/flavors" tplink-tl-wdr4300-v1-minimal-25.12.5)"
python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["flavor"] == "minimal"
assert (data["openwrt_source"], data["openwrt_version"]) == ("release", "25.12.5")
assert data["openwrt_profile"] == "tplink_tl-wdr4300-v1"
assert (data["target"], data["subtarget"]) == ("ath79", "generic")
assert "audiowrt-minimal-alsa" in data["packages_add"]
assert "alsa-lib" in data["packages_remove"]
' <<< "$wdr"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$repo_root/profiles/tplink-tl-wdr4300-v1-minimal-25.12.5.yaml" \
    "$tmp/example-device-full-snapshot.yaml"
snapshot="$(python3 "$repo_root/scripts/resolve-audiowrt-profile.py" \
    "$tmp" "$repo_root/config/flavors" example-device-full-snapshot)"
python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["device"] == "example-device"
assert data["flavor"] == "full"
assert data["openwrt_source"] == "snapshot"
assert data["openwrt_version"] == "snapshot"
' <<< "$snapshot"

grep -q 'AUDIOWRT_PROFILE:-tplink-tl-wdr4300-v1-minimal-25.12.5' "$repo_root/scripts/build.sh"
echo 'AudioWRT flavor and device profile tests passed.'
