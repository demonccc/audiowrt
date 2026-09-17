#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
targets="$repo_root/config/build/package-build-targets"
sources="$repo_root/config/build/source-build-packages"
build_script="$repo_root/scripts/build.sh"
resolver="$repo_root/scripts/resolve-audiowrt-profile.py"
groups="$repo_root/config/package-groups"

resolved="$(python3 "$resolver" \
    "$repo_root/profiles" \
    "$groups" \
    tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5)"

python3 -c '
import json, sys
data = json.load(sys.stdin)
added = set(data["packages_add"])
removed = set(data["packages_remove"])
assert {
    "audiowrt-minimal-alsa",
    "audiowrt-minimal-mbedtls",
    "audiowrt-dropbear",
    "audiowrt-wpa-supplicant",
    "mpd-mini",
    "upmpdcli",
    "audiowrt-minimal-upmpdcli",
    "audiowrt-mpd",
    "umdns",
    "kmod-audiowrt-bluetooth",
} <= added
assert {
    "alsa-lib",
    "libmbedtls21",
    "dropbear",
    "wpad-basic-mbedtls",
    "mpd-full",
    "minidlna",
    "kmod-sound-midi2",
    "kmod-sound-midi2-usb",
} <= removed
assert not ({"alsa-lib", "libmbedtls21", "dropbear", "wpad-basic-mbedtls", "mpd-full", "minidlna"} & added)
assert "mpd-mini" not in removed
assert "upmpdcli" not in removed
assert "umdns" not in removed
assert "audiowrt-umdns" not in added
assert "audiowrt-minimal-mpd" not in added
' <<< "$resolved"

for package in \
    audiowrt-minimal-alsa \
    audiowrt-minimal-mbedtls \
    audiowrt-dropbear \
    audiowrt-wpa-supplicant \
    audiowrt-minimal-upmpdcli; do
    grep -q "^${package}|package/feeds/audiowrt/${package}/compile$" "$targets"
done

if grep -q '^audiowrt-minimal-mpd|' "$targets"; then
    echo 'ERROR: removed custom MPD source package is still registered as an SDK target.' >&2
    exit 1
fi

grep -qx 'kmod-audiowrt-bluetooth|package/feeds/audiowrt/audiowrt-kmod-bluetooth/compile' "$targets"

for package in audiowrt-minimal-alsa audiowrt-minimal-mbedtls audiowrt-dropbear; do
    grep -qx "$package" "$sources"
done
for package in audiowrt-wpa-supplicant audiowrt-minimal-upmpdcli audiowrt-minimal-mpd audiowrt-umdns mpd-mini upmpdcli; do
    if grep -qx "$package" "$sources"; then
        echo "ERROR: $package must reuse official runtime binaries or NO_DEPS=1 and must not be a source-build root." >&2
        exit 1
    fi
done

for keep in bluetooth.ko btmtk.ko btintel.ko btrtl.ko btusb.ko; do
    grep -Fq "$keep" "$build_script"
done
for drop in rfcomm.ko bnep.ko hidp.ko; do
    grep -Fq "$drop" "$build_script"
done

grep -Fq 'find "$sdk_dir/bin/targets/$target/$subtarget/packages"' "$build_script"
grep -Fq -- "-name 'kmod-audiowrt-*.apk'" "$build_script"
grep -Fq 'SDK build did not produce selected AudioWRT package' "$build_script"

grep -q 'kmods_sha256sums_url' "$repo_root/scripts/resolve-openwrt-artifacts.py"
grep -q '"kmods_sha256sums_url": urljoin(base_url, "sha256sums")' "$repo_root/scripts/resolve-openwrt-artifacts.py"

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
fixture_name='kmod-bluetooth-6.12.94-r1.apk'
fixture_relative="kmods/6.12.94-1-test/$fixture_name"
printf 'exact OpenWrt APK fixture\n' > "$fixture_dir/$fixture_name"
fixture_checksum="$(sha256sum "$fixture_dir/$fixture_name" | awk '{print $1}')"
printf '%s *%s\n' "$fixture_checksum" "$fixture_relative" > "$fixture_dir/sha256sums"

python3 "$repo_root/scripts/verify-openwrt-checksum.py" \
    "$fixture_dir/sha256sums" "$fixture_relative" "$fixture_dir/$fixture_name"

if python3 "$repo_root/scripts/verify-openwrt-checksum.py" \
    "$fixture_dir/sha256sums" "kmods/wrong/$fixture_name" "$fixture_dir/$fixture_name" 2>/dev/null; then
    echo 'Checksum verification accepted the wrong target-relative path.' >&2
    exit 1
fi

printf 'tampered\n' >> "$fixture_dir/$fixture_name"
if python3 "$repo_root/scripts/verify-openwrt-checksum.py" \
    "$fixture_dir/sha256sums" "$fixture_relative" "$fixture_dir/$fixture_name" 2>/dev/null; then
    echo 'Checksum verification accepted a modified APK.' >&2
    exit 1
fi

echo 'Minimal runtime stack distribution contracts passed.'
