#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
targets="$repo_root/config/build/package-build-targets"
sources="$repo_root/config/build/source-build-packages"
build_script="$repo_root/scripts/build.sh"
resolver="$repo_root/scripts/resolve-audiowrt-profile.py"
groups="$repo_root/config/package-groups"

minimal="$(python3 "$resolver" \
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
    "audiowrt-wpad",
    "audiowrt-renderer",
    "audiowrt-player-core",
    "audiowrt-player-flac",
    "luci-app-audiowrt-renderer",
    "kmod-audiowrt-bluetooth",
} <= added
assert {
    "alsa-lib",
    "libmbedtls21",
    "dropbear",
    "wpad-basic-mbedtls",
    "mpd-mini",
    "mpd-full",
    "upmpdcli",
    "audiowrt-minimal-upmpdcli",
    "audiowrt-mpd",
    "minidlna",
    "umdns",
    "audiowrt-umdns",
    "kmod-sound-midi2",
    "kmod-sound-midi2-usb",
    "audiowrt-player-mp3",
    "libmpg123",
    "libltdl",
} <= removed
assert not ({
    "mpd-mini", "mpd-full", "upmpdcli", "audiowrt-minimal-upmpdcli",
    "audiowrt-mpd", "minidlna", "umdns", "audiowrt-umdns",
    "audiowrt-player-mp3", "audiowrt-player-aac", "audiowrt-player-wav"
} & added)
' <<< "$minimal"

standard="$(python3 "$resolver" \
    "$repo_root/profiles" \
    "$groups" \
    x86-64-usb-bluetooth-audio-25.12.5)"

python3 -c '
import json, sys
data = json.load(sys.stdin)
added = set(data["packages_add"])
removed = set(data["packages_remove"])
assert {
    "audiowrt-renderer",
    "audiowrt-player-core",
    "audiowrt-player-flac",
    "audiowrt-player-mp3",
    "audiowrt-player-aac",
    "audiowrt-player-wav",
    "luci-app-audiowrt-renderer",
} <= added
assert {"mpd-mini", "mpd-full", "upmpdcli", "audiowrt-mpd", "minidlna", "umdns", "audiowrt-umdns"} <= removed
assert not ({"mpd-mini", "mpd-full", "upmpdcli", "audiowrt-mpd", "minidlna", "umdns", "audiowrt-umdns"} & added)
' <<< "$standard"

for package in \
    audiowrt-minimal-alsa \
    audiowrt-minimal-mbedtls \
    audiowrt-dropbear \
    audiowrt-wpad \
    audiowrt-renderer \
    audiowrt-player-core \
    audiowrt-player-flac \
    audiowrt-player-mp3 \
    audiowrt-player-aac \
    audiowrt-player-wav \
    luci-app-audiowrt-renderer; do
    grep -q "^${package}|package/feeds/audiowrt/" "$targets"
done

grep -qx 'kmod-audiowrt-bluetooth|package/feeds/audiowrt/audiowrt-kmod-bluetooth/compile' "$targets"

# The constrained runtime packages compile AudioWRT-owned source with
# NO_DEPS=1. Runtime-only OpenWrt dependencies (including kernel modules) must
# not turn into source-build roots.
for package in \
    audiowrt-minimal-alsa \
    audiowrt-minimal-mbedtls \
    audiowrt-dropbear \
    audiowrt-wpad \
    audiowrt-busybox \
    audiowrt-sbc \
    audiowrt-bluez-libs \
    audiowrt-btctl \
    audiowrt-renderer \
    audiowrt-player-core \
    audiowrt-player-flac \
    audiowrt-player-mp3 \
    audiowrt-player-aac \
    audiowrt-player-wav \
    audiowrt-minimal-upmpdcli \
    audiowrt-mpd \
    audiowrt-umdns \
    mpd-mini \
    upmpdcli \
    luci-app-audiowrt-renderer; do
    if grep -qx "$package" "$sources"; then
        echo "ERROR: $package must not be a source-build root." >&2
        exit 1
    fi
done

for package in audiowrt-bluez bluez-alsa; do
    grep -qx "$package" "$sources" || {
        echo "ERROR: $package must remain an explicit upstream source root." >&2
        exit 1
    }
done

# AudioWRT's multicall wpad compiles the exact upstream hostap source behind
# NO_DEPS=1. Its build interfaces are staged once so hostapd-common/ubus/ucode
# never become recursive source roots.
grep -Fq 'prepare_hostap_sdk()' "$build_script"
grep -Fq 'audiowrt-wpad' "$build_script"
grep -Fq 'package/feeds/base/libnl-tiny/compile' "$build_script"
grep -Fq 'package/feeds/base/libjson-c/compile' "$build_script"
grep -Fq 'register_official_sdk_source base libs/libjson-c' "$build_script"
grep -Fq 'json-c/json.h' "$build_script"
for package in libubox ubus ucode udebug; do
    grep -Fq "package/feeds/base/$package/prepare" "$build_script"
done
for package in libubox libblobmsg-json libubus libucode libudebug; do
    grep -Fq "stage_official_link_stub $package base" "$build_script"
done
grep -Fq -- '--all-dynamic-symbols' "$build_script"
grep -Fq "stage_official_link_stub libudebug base 'libudebug.so*' libudebug.so" "$build_script"

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

echo 'Unified renderer runtime stack distribution contracts passed.'
