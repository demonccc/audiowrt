#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages="$repo_root/config/flavors/minimal/packages.add"
targets="$repo_root/config/package-build-targets"
sources="$repo_root/config/source-build-packages"
removed="$repo_root/config/flavors/minimal/packages.remove"
build_script="$repo_root/scripts/build.sh"

grep -qx 'audiowrt-minimal-mbedtls' "$packages"
grep -qx 'audiowrt-minimal-alsa|package/feeds/audiowrt/audiowrt-minimal-alsa/compile' "$targets"
grep -qx 'audiowrt-minimal-mbedtls|package/feeds/audiowrt/audiowrt-minimal-mbedtls/compile' "$targets"
grep -qx 'kmod-audiowrt-bluetooth|package/feeds/audiowrt/audiowrt-kmod-bluetooth/compile' "$targets"
grep -qx 'audiowrt-minimal-alsa' "$sources"
grep -qx 'audiowrt-minimal-mbedtls' "$sources"

grep -qx 'kmod-sound-midi2' "$removed"
grep -qx 'kmod-sound-midi2-usb' "$removed"

for keep in bluetooth.ko btmtk.ko btintel.ko btrtl.ko btusb.ko; do
    grep -Fq "$keep" "$build_script"
done
for drop in rfcomm.ko bnep.ko hidp.ko; do
    grep -Fq "$drop" "$build_script"
done

grep -q 'kmods_sha256sums_url' "$repo_root/scripts/resolve-openwrt-artifacts.py"
grep -q 'sha256sum -c' "$build_script"

echo 'Minimal runtime stack distribution contracts passed.'
