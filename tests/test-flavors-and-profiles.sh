#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$repo_root/scripts/resolve-audiowrt-profile.py"
groups="$repo_root/config/package-groups"

for group in \
    common \
    minimal \
    standard \
    minimal-usb-audio \
    minimal-usb-bluetooth \
    minimal-usb-audio-bluetooth \
    usb-audio \
    usb-bluetooth \
    usb-audio-bluetooth; do
    test -s "$groups/$group.yaml"
done

test ! -e "$repo_root/config/flavors"

# Global AudioWRT policy belongs to common and common is automatic. The native
# renderer/discovery service is part of every AudioWRT image; codec/player
# choices remain in minimal/standard.
for package in \
    audiowrt-branding \
    audiowrt-udhcpd \
    audiowrt-renderer \
    luci-app-audiowrt-renderer \
    luci-base \
    luci-mod-status \
    luci-mod-system \
    luci-app-package-manager; do
    grep -q "^  - $package$" "$groups/common.yaml"
done
for package in dropbear wpad-basic-mbedtls mpd-mini upmpdcli; do
    ! grep -q "^  - $package$" "$groups/common.yaml"
done
for package in \
    busybox \
    dnsmasq \
    firewall4 \
    ppp \
    ppp-mod-pppoe \
    luci \
    luci-light \
    luci-mod-admin-full \
    luci-mod-network \
    luci-app-firewall \
    luci-proto-ppp \
    minidlna \
    umdns \
    audiowrt-umdns; do
    grep -q "^  - $package$" "$groups/common.yaml"
done

# Minimal runtime uses the AudioWRT native renderer/discovery daemon plus the
# FLAC player only. MP3/AAC/WAV, MPD/upmpdcli and a separate mDNS daemon must
# remain absent from the constrained image.
for package in \
    audiowrt-minimal-alsa \
    audiowrt-minimal-mbedtls \
    audiowrt-dropbear \
    audiowrt-wpa-supplicant \
    audiowrt-player-core \
    audiowrt-player-flac; do
    grep -q "^  - $package$" "$groups/minimal.yaml"
done
for package in \
    alsa-lib \
    libmbedtls21 \
    dropbear \
    wpad-basic-mbedtls \
    mpd-mini \
    mpd-full \
    upmpdcli \
    audiowrt-minimal-upmpdcli \
    audiowrt-mpd \
    audiowrt-player-mp3 \
    libmpg123 \
    libltdl; do
    grep -q "^  - $package$" "$groups/minimal.yaml"
done
for package in audiowrt-player-mp3 audiowrt-player-aac audiowrt-player-wav; do
    ! grep -q "^  - $package$" "$groups/minimal.yaml"
done
for group in minimal-usb-audio minimal-usb-bluetooth minimal-usb-audio-bluetooth; do
    grep -A1 '^include:$' "$groups/$group.yaml" | grep -q '^  - minimal$'
done

# Standard runtime uses the same renderer/discovery core but installs all four
# official AudioWRT codec players.
for package in \
    alsa-lib \
    libmbedtls21 \
    dropbear \
    wpad-basic-mbedtls \
    audiowrt-player-core \
    audiowrt-player-flac \
    audiowrt-player-mp3 \
    audiowrt-player-aac \
    audiowrt-player-wav; do
    grep -q "^  - $package$" "$groups/standard.yaml"
done
for package in \
    audiowrt-minimal-alsa \
    audiowrt-minimal-mbedtls \
    audiowrt-dropbear \
    audiowrt-wpa-supplicant \
    audiowrt-minimal-upmpdcli \
    mpd-mini \
    mpd-full \
    upmpdcli \
    audiowrt-mpd; do
    grep -q "^  - $package$" "$groups/standard.yaml"
done
for group in usb-audio usb-bluetooth usb-audio-bluetooth; do
    grep -A1 '^include:$' "$groups/$group.yaml" | grep -q '^  - standard$'
done

for profile_file in "$repo_root"/profiles/*.yaml; do
    profile="$(basename "$profile_file" .yaml)"
    resolved="$(python3 "$resolver" "$repo_root/profiles" "$groups" "$profile")"
    python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["id"] == sys.argv[1]
assert isinstance(data["package_groups"], list)
assert "flavor" not in data
assert data["openwrt_source"] in {"release", "snapshot"}
assert not set(data["packages_add"]) & set(data["packages_remove"])
assert "audiowrt-branding" in data["packages_add"]
assert "audiowrt-udhcpd" in data["packages_add"]
assert "audiowrt-renderer" in data["packages_add"]
assert "luci-app-audiowrt-renderer" in data["packages_add"]
for package in ("dnsmasq", "ppp", "ppp-mod-pppoe", "luci-proto-ppp", "luci-app-firewall", "luci-mod-network", "minidlna", "umdns", "audiowrt-umdns"):
    assert package in data["packages_remove"]
' "$profile" <<< "$resolved"
done

wdr_bt="$(python3 "$resolver" "$repo_root/profiles" "$groups" tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5)"
python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["package_groups"] == ["minimal-usb-bluetooth"]
assert data["openwrt_profile"] == "tplink_tl-wdr4300-v1"
assert data["squashfs_block_size"] == "1024"
added = set(data["packages_add"])
removed = set(data["packages_remove"])
assert {
    "audiowrt-minimal-alsa", "audiowrt-minimal-mbedtls", "audiowrt-dropbear",
    "audiowrt-wpa-supplicant", "audiowrt-renderer", "audiowrt-player-core",
    "audiowrt-player-flac", "luci-app-audiowrt-renderer",
    "kmod-audiowrt-bluetooth"
} <= added
assert {
    "alsa-lib", "libmbedtls21", "dropbear", "wpad-basic-mbedtls", "mpd-mini",
    "mpd-full", "upmpdcli", "audiowrt-minimal-upmpdcli", "audiowrt-mpd",
    "minidlna", "umdns", "audiowrt-umdns", "dnsmasq", "kmod-bluetooth",
    "kmod-usb-audio", "audiowrt-player-mp3", "libmpg123", "libltdl"
} <= removed
assert not ({"audiowrt-player-mp3", "audiowrt-player-aac", "audiowrt-player-wav", "mpd-mini", "upmpdcli", "umdns"} & added)
' <<< "$wdr_bt"

wdr_audio="$(python3 "$resolver" "$repo_root/profiles" "$groups" tplink-tl-wdr4300-v1-minimal-usb-audio-25.12.5)"
python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["package_groups"] == ["minimal-usb-audio"]
assert data["openwrt_profile"] == "tplink_tl-wdr4300-v1"
added = set(data["packages_add"])
removed = set(data["packages_remove"])
assert {
    "audiowrt-minimal-alsa", "audiowrt-minimal-mbedtls", "audiowrt-dropbear",
    "audiowrt-wpa-supplicant", "audiowrt-renderer", "audiowrt-player-core",
    "audiowrt-player-flac", "luci-app-audiowrt-renderer",
    "audiowrt-usb-audio", "kmod-usb-audio"
} <= added
assert {
    "alsa-lib", "libmbedtls21", "dropbear", "wpad-basic-mbedtls", "mpd-mini",
    "mpd-full", "upmpdcli", "audiowrt-minimal-upmpdcli", "audiowrt-mpd",
    "minidlna", "umdns", "audiowrt-umdns", "dnsmasq", "kmod-bluetooth",
    "kmod-audiowrt-bluetooth", "audiowrt-player-mp3", "libmpg123", "libltdl"
} <= removed
assert not ({
    "audiowrt-player-mp3", "audiowrt-player-aac", "audiowrt-player-wav", "mpd-mini", "upmpdcli", "umdns",
    "audiowrt-bluetooth", "audiowrt-bluez", "audiowrt-bluez-libs",
    "audiowrt-btctl", "audiowrt-sbc", "bluez-alsa",
    "kmod-sound-midi2", "kmod-sound-midi2-usb"
} & added)
' <<< "$wdr_audio"

# Package groups may include reusable groups; current group entries apply last.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/groups" "$tmp/profiles"
cat > "$tmp/groups/common.yaml" <<'EOF'
schema_version: 1
packages_add: []
packages_remove: []
EOF
cat > "$tmp/groups/base.yaml" <<'EOF'
schema_version: 1
packages_add:
  - inherited-package
  - overridden-package
packages_remove: []
EOF
cat > "$tmp/groups/child.yaml" <<'EOF'
schema_version: 1
include:
  - base
packages_add:
  - child-package
packages_remove:
  - overridden-package
EOF
cat > "$tmp/profiles/example-device-test-25.12.5.yaml" <<'EOF'
schema_version: 1
status: candidate
maintainer_github: demonccc
openwrt_profile: example
target: example
subtarget: generic
package_groups:
  - child
packages_add: []
packages_remove: []
EOF
resolved="$(python3 "$resolver" "$tmp/profiles" "$tmp/groups" example-device-test-25.12.5)"
python3 -c '
import json,sys
d=json.load(sys.stdin)
assert "inherited-package" in d["packages_add"]
assert "child-package" in d["packages_add"]
assert "overridden-package" not in d["packages_add"]
assert "overridden-package" in d["packages_remove"]
' <<< "$resolved"

# Include cycles must fail explicitly.
cat > "$tmp/groups/cycle-a.yaml" <<'EOF'
schema_version: 1
include:
  - cycle-b
packages_add: []
packages_remove: []
EOF
cat > "$tmp/groups/cycle-b.yaml" <<'EOF'
schema_version: 1
include:
  - cycle-a
packages_add: []
packages_remove: []
EOF
sed -i 's/  - child/  - cycle-a/' "$tmp/profiles/example-device-test-25.12.5.yaml"
if python3 "$resolver" "$tmp/profiles" "$tmp/groups" example-device-test-25.12.5 >/dev/null 2>&1; then
    echo "ERROR: package group include cycle should have failed." >&2
    exit 1
fi

grep -q 'AUDIOWRT_PROFILE:-tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5' "$repo_root/scripts/build.sh"
grep -q 'CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=' "$repo_root/scripts/build.sh"
grep -q 'config/build/package-build-targets' "$repo_root/scripts/build.sh"
grep -q 'config/build/source-build-packages' "$repo_root/scripts/build.sh"
! grep -q 'check-usb.py' "$repo_root/scripts/build.sh"

echo 'AudioWRT package group and device profile tests passed.'
