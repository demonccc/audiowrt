#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/targets" <<'EOF'
audiowrt-core|package/feeds/audiowrt/audiowrt-core/compile
audiowrt-busybox|package/feeds/audiowrt/audiowrt-busybox/compile
audiowrt-provisioning|package/feeds/audiowrt/audiowrt-provisioning/compile
audiowrt-wpad|package/feeds/audiowrt/audiowrt-wpad/compile
audiowrt-udhcpd|package/feeds/audiowrt/audiowrt-udhcpd/compile
audiowrt-storage|package/feeds/audiowrt/audiowrt-storage/compile
audiowrt-storage-luci|package/feeds/audiowrt/luci-app-audiowrt-storage/compile
kmod-audiowrt-bluetooth|package/feeds/audiowrt/audiowrt-kmod-bluetooth/compile
kmod-audiowrt-sound-core|package/feeds/audiowrt/packages/audiowrt-kmod-sound-core/compile
kmod-audiowrt-usb-audio|package/feeds/audiowrt/packages/audiowrt-kmod-usb-audio/compile
audiowrt-audio|package/feeds/audiowrt/audiowrt-audio/compile
audiowrt-minimal-alsa|package/feeds/audiowrt/audiowrt-minimal-alsa/compile
audiowrt-extensions|package/feeds/audiowrt/audiowrt-extensions/compile
audiowrt-wifi-client|package/feeds/audiowrt/audiowrt-wifi-client/compile
luci-app-audiowrt-wifi-client|package/feeds/audiowrt/luci-app-audiowrt-wifi-client/compile
audiowrt-spotify|package/feeds/audiowrt/audiowrt-spotify/compile
librespot|package/feeds/audiowrt/librespot/compile
audiowrt-sbc|package/feeds/audiowrt/audiowrt-sbc/compile
audiowrt-bluez-libs|package/feeds/audiowrt/audiowrt-bluez/compile
audiowrt-bluez|package/feeds/audiowrt/audiowrt-bluez/compile
audiowrt-btctl|package/feeds/audiowrt/audiowrt-btctl/compile
bluez-alsa|package/feeds/audiowrt/bluez-alsa/compile
audiowrt-bluetooth|package/feeds/audiowrt/audiowrt-bluetooth/compile
EOF

cat > "$tmp/packageinfo" <<'EOF'
Package: audiowrt-core
Depends: +libc +audiowrt-audio
Package: audiowrt-busybox
Depends: +libc
Package: audiowrt-provisioning
Depends: +audiowrt-core +audiowrt-wifi-client +hostapd +audiowrt-udhcpd
Package: audiowrt-wpad
Depends: +libnl-tiny +hostapd-common +libubus +libucode +libmbedtls
Provides: hostapd wpa-supplicant
Package: audiowrt-udhcpd
Depends: +audiowrt-busybox
Package: audiowrt-storage
Depends: +audiowrt-core +block-mount +kmod-usb-storage +kmod-fs-ext4 +e2fsprogs
Package: audiowrt-storage-luci
Depends: +luci-base +rpcd-mod-file +luci-app-audiowrt +audiowrt-storage
Package: audiowrt-audio
Depends: +uci
Package: audiowrt-extensions
Depends: +audiowrt-audio +apk-mbedtls
Package: audiowrt-wifi-client
Depends: +uci +ubus +rpcd-mod-iwinfo +wpa-supplicant
Package: luci-app-audiowrt-wifi-client
Depends: +luci-base +audiowrt-wifi-client
Package: audiowrt-spotify
Depends: +audiowrt-extensions +librespot
Package: librespot
Depends: +alsa-lib
Package: audiowrt-sbc
Depends: +libc
Package: audiowrt-bluez-libs
Depends: +libpthread
Package: audiowrt-bluez
Depends: +audiowrt-bluez-libs +glib2 +dbus +alsa-lib
Package: audiowrt-minimal-alsa
Depends: +kmod-sound-core
Provides: alsa-lib
Package: audiowrt-btctl
Depends: +glib2
Package: bluez-alsa
Depends: +alsa-lib +audiowrt-bluez +audiowrt-bluez-libs +glib2 +audiowrt-sbc +dbus
Package: audiowrt-bluetooth
Depends: +audiowrt-audio +audiowrt-bluez +audiowrt-btctl +bluez-alsa +kmod-bluetooth +kmod-btusb
Package: kmod-audiowrt-bluetooth
Depends: +kernel +kmod-usb-core
Package: kmod-audiowrt-sound-core
Depends: +kernel +kmod-input-core
Package: kmod-audiowrt-usb-audio
Depends: +kernel +kmod-usb-core +kmod-audiowrt-sound-core +kmod-media-controller +kmod-sound-midi2
EOF

resolver="$repo_root/scripts/resolve-package-build-targets.py"

python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-core audiowrt-provisioning audiowrt-wpad audiowrt-extensions luci-app-audiowrt-wifi-client > "$tmp/core"

grep -q '^audiowrt-audio|' "$tmp/core"
grep -q '^audiowrt-core|' "$tmp/core"
grep -q '^audiowrt-provisioning|' "$tmp/core"
grep -q '^audiowrt-wpad|' "$tmp/core"
grep -q '^audiowrt-udhcpd|' "$tmp/core"
grep -q '^audiowrt-busybox|' "$tmp/core"
grep -q '^audiowrt-wifi-client|' "$tmp/core"
grep -q '^luci-app-audiowrt-wifi-client|' "$tmp/core"
grep -q '^audiowrt-extensions|' "$tmp/core"
if grep -Eq '^(audiowrt-storage|audiowrt-storage-luci|audiowrt-spotify|librespot|audiowrt-bluetooth|bluez-alsa|audiowrt-bluez|audiowrt-bluez-libs|audiowrt-sbc|audiowrt-btctl)\|' "$tmp/core"; then
    echo "ERROR: non-Bluetooth core roots selected unrelated AudioWRT packages." >&2
    cat "$tmp/core" >&2
    exit 1
fi

python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-core audiowrt-storage-luci > "$tmp/storage"
grep -q '^audiowrt-storage|' "$tmp/storage"
grep -q '^audiowrt-storage-luci|' "$tmp/storage"

python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-core audiowrt-extensions audiowrt-spotify > "$tmp/spotify"
grep -q '^librespot|' "$tmp/spotify"
grep -q '^audiowrt-spotify|' "$tmp/spotify"
if grep -Eq '^(audiowrt-bluetooth|bluez-alsa|audiowrt-bluez|audiowrt-bluez-libs|audiowrt-sbc|audiowrt-btctl)\|' "$tmp/spotify"; then
    echo "ERROR: Spotify build selected Bluetooth packages." >&2
    exit 1
fi

# The Bluetooth root includes the BlueZ package that carries A2DP/AVRCP; the
# minimal ALSA and Bluetooth kernel packages are part of
# the AudioWRT-owned dependency closure.
python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-core audiowrt-extensions audiowrt-minimal-alsa kmod-audiowrt-bluetooth \
    kmod-audiowrt-sound-core kmod-audiowrt-usb-audio audiowrt-bluetooth > "$tmp/bluetooth"
for package in audiowrt-minimal-alsa audiowrt-sbc audiowrt-bluez-libs audiowrt-bluez audiowrt-btctl bluez-alsa kmod-audiowrt-bluetooth audiowrt-bluetooth; do
    grep -q "^${package}|" "$tmp/bluetooth"
done
for package in kmod-audiowrt-sound-core kmod-audiowrt-usb-audio; do
    grep -q "^${package}|" "$tmp/bluetooth"
done
if grep -Eq '^(audiowrt-spotify|librespot)\|' "$tmp/bluetooth"; then
    echo "ERROR: Bluetooth baseline selected Spotify packages." >&2
    exit 1
fi

printf 'Package build selection tests passed.\n'
