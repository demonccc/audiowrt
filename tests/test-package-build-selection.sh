#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/targets" <<'EOF'
audiowrt-core|package/feeds/audiowrt/audiowrt-core/compile
audiowrt-config|package/feeds/audiowrt/audiowrt-config/compile
audiowrt-identity|package/feeds/audiowrt/audiowrt-identity/compile
audiowrt-busybox|package/feeds/audiowrt/audiowrt-busybox/compile
audiowrt-provisioning|package/feeds/audiowrt/audiowrt-provisioning/compile
audiowrt-wpad|package/feeds/audiowrt/audiowrt-wpad/compile
audiowrt-udhcpd|package/feeds/audiowrt/audiowrt-udhcpd/compile
kmod-audiowrt-bluetooth|package/feeds/audiowrt/audiowrt-kmod-bluetooth/compile
kmod-audiowrt-sound-core|package/feeds/audiowrt/packages/audiowrt-kmod-sound-core/compile
kmod-audiowrt-usb-audio|package/feeds/audiowrt/packages/audiowrt-kmod-usb-audio/compile
audiowrt-audio|package/feeds/audiowrt/audiowrt-audio/compile
libaudiowrt-alsa-minimal|package/feeds/audiowrt/libaudiowrt-alsa-minimal/compile
libaudiowrt-player|package/feeds/audiowrt/libaudiowrt-player/compile
audiowrt-player-flac|package/feeds/audiowrt/audiowrt-player-flac/compile
audiowrt-player-mp3|package/feeds/audiowrt/audiowrt-player-mp3/compile
audiowrt-player-aac|package/feeds/audiowrt/audiowrt-player-aac/compile
audiowrt-player-m4a|package/feeds/audiowrt/audiowrt-player-m4a/compile
audiowrt-player-lpcm|package/feeds/audiowrt/audiowrt-player-lpcm/compile
audiowrt-player-wav|package/feeds/audiowrt/audiowrt-player-wav/compile
audiowrt-player-vorbis|package/feeds/audiowrt/audiowrt-player-vorbis/compile
audiowrt-player-aiff|package/feeds/audiowrt/audiowrt-player-aiff/compile
audiowrt-player-opus|package/feeds/audiowrt/audiowrt-player-opus/compile
audiowrt-player-ffmpeg|package/feeds/audiowrt/audiowrt-player-ffmpeg/compile
audiowrt-extensions|package/feeds/audiowrt/audiowrt-extensions/compile
audiowrt-network-client|package/feeds/audiowrt/audiowrt-network-client/compile
audiowrt-wifi-client|package/feeds/audiowrt/audiowrt-wifi-client/compile
luci-app-audiowrt-network-client|package/feeds/audiowrt/luci-app-audiowrt-network-client/compile
luci-app-audiowrt-wifi-client|package/feeds/audiowrt/luci-app-audiowrt-wifi-client/compile
audiowrt-spotify|package/feeds/audiowrt/audiowrt-spotify/compile
librespot|package/feeds/audiowrt/librespot/compile
audiowrt-sbc|package/feeds/audiowrt/audiowrt-sbc/compile
audiowrt-bluez|package/feeds/audiowrt/audiowrt-bluez/compile
audiowrt-btctl|package/feeds/audiowrt/audiowrt-btctl/compile
bluez-alsa|package/feeds/audiowrt/bluez-alsa/compile
audiowrt-bluetooth|package/feeds/audiowrt/audiowrt-bluetooth/compile
EOF

cat > "$tmp/packageinfo" <<'EOF'
Package: audiowrt-core
Depends: +libc +audiowrt-audio +audiowrt-identity
Package: audiowrt-busybox
Depends: +libc
Package: audiowrt-provisioning
Depends: +audiowrt-core +audiowrt-wifi-client +hostapd +audiowrt-udhcpd
Package: audiowrt-wpad
Depends: +libnl-tiny +hostapd-common +libubus +libucode +libmbedtls
Provides: hostapd wpa-supplicant
Package: audiowrt-udhcpd
Depends: +audiowrt-busybox
Package: audiowrt-config
Depends: +uci
Package: audiowrt-identity
Depends: +libc
Package: audiowrt-audio
Depends: +uci
Package: audiowrt-extensions
Depends: +audiowrt-audio +apk-mbedtls
Package: audiowrt-network-client
Depends: +audiowrt-config +uci +ubus +netifd
Package: audiowrt-wifi-client
Depends: +audiowrt-config +uci +ubus +rpcd-mod-iwinfo +wpa-supplicant
Package: luci-app-audiowrt-network-client
Depends: +luci-base +audiowrt-network-client +audiowrt-wifi-client
Package: luci-app-audiowrt-wifi-client
Depends: +luci-app-audiowrt-network-client
Package: audiowrt-spotify
Depends: +audiowrt-extensions +librespot
Package: librespot
Depends: +alsa-lib
Package: audiowrt-sbc
Depends: +libc
Package: audiowrt-bluez
Depends: +bluez-libs +glib2 +dbus +alsa-lib
Package: libaudiowrt-alsa-minimal
Depends: +kmod-sound-core
Provides: alsa-lib
Package: libaudiowrt-player
Depends: +alsa-lib +libuclient +libustream-mbedtls
Package: audiowrt-player-flac
Depends: +libaudiowrt-player +libflac +libpthread
Package: audiowrt-player-mp3
Depends: +libaudiowrt-player +libmad +libpthread
Package: audiowrt-player-aac
Depends: +libaudiowrt-player +libfaad2 +libpthread
Package: audiowrt-player-m4a
Depends: +libaudiowrt-player +faad2
Package: audiowrt-player-lpcm
Depends: +libaudiowrt-player +libpthread
Package: audiowrt-player-wav
Depends: +libaudiowrt-player +libpthread
Package: audiowrt-player-vorbis
Depends: +libaudiowrt-player +libvorbis +libpthread
Package: audiowrt-player-aiff
Depends: +libaudiowrt-player +libpthread
Package: audiowrt-player-opus
Depends: +libaudiowrt-player +libopusfile +libpthread
Package: audiowrt-player-ffmpeg
Depends: +libaudiowrt-player +ffmpeg
Package: audiowrt-btctl
Depends: +glib2
Package: bluez-alsa
Depends: +alsa-lib +audiowrt-bluez +bluez-libs +glib2 +audiowrt-sbc +dbus
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
    audiowrt-core audiowrt-provisioning audiowrt-wpad audiowrt-extensions luci-app-audiowrt-network-client > "$tmp/core"

grep -q '^audiowrt-audio|' "$tmp/core"
grep -q '^audiowrt-core|' "$tmp/core"
grep -q '^audiowrt-provisioning|' "$tmp/core"
grep -q '^audiowrt-wpad|' "$tmp/core"
grep -q '^audiowrt-udhcpd|' "$tmp/core"
grep -q '^audiowrt-busybox|' "$tmp/core"
grep -q '^audiowrt-network-client|' "$tmp/core"
grep -q '^audiowrt-wifi-client|' "$tmp/core"
grep -q '^luci-app-audiowrt-network-client|' "$tmp/core"
grep -q '^audiowrt-extensions|' "$tmp/core"
if grep -Eq '^(audiowrt-storage|audiowrt-storage-luci|audiowrt-spotify|librespot|audiowrt-bluetooth|bluez-alsa|audiowrt-bluez|audiowrt-btctl)\|' "$tmp/core"; then
    echo "ERROR: non-Bluetooth core roots selected unrelated AudioWRT packages." >&2
    cat "$tmp/core" >&2
    exit 1
fi

# A standalone Network Client build still resolves the profile's AudioWRT wpad
# provider through the virtual wpa-supplicant dependency. The builder must use
# this resolved closure, not only the explicit package root, when deciding which
# SDK development interfaces to stage.
python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    luci-app-audiowrt-network-client \
    --providers audiowrt-wpad > "$tmp/network-client"
grep -q '^audiowrt-network-client|' "$tmp/network-client"
grep -q '^audiowrt-wifi-client|' "$tmp/network-client"
grep -q '^audiowrt-wpad|' "$tmp/network-client"
grep -q '^luci-app-audiowrt-network-client|' "$tmp/network-client"

# A standalone package request must include its AudioWRT-owned build dependency
# closure without selecting unrelated packages.
python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-player-flac \
    --providers libaudiowrt-alsa-minimal > "$tmp/flac"
grep -q '^libaudiowrt-alsa-minimal|' "$tmp/flac"
grep -q '^libaudiowrt-player|' "$tmp/flac"
grep -q '^audiowrt-player-flac|' "$tmp/flac"
if grep -Eq '^(audiowrt-core|audiowrt-bluetooth|audiowrt-spotify|librespot)\|' "$tmp/flac"; then
    echo "ERROR: standalone FLAC package build selected unrelated AudioWRT packages." >&2
    cat "$tmp/flac" >&2
    exit 1
fi

python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-player-flac > "$tmp/flac-official-alsa"
if grep -q '^libaudiowrt-alsa-minimal|' "$tmp/flac-official-alsa"; then
    echo "ERROR: resolver selected a profile provider that was not supplied." >&2
    cat "$tmp/flac-official-alsa" >&2
    exit 1
fi

for player in audiowrt-player-mp3 audiowrt-player-aac audiowrt-player-m4a audiowrt-player-lpcm audiowrt-player-wav audiowrt-player-vorbis audiowrt-player-aiff audiowrt-player-opus audiowrt-player-ffmpeg; do
    out="$tmp/${player}"
    python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" "$player" \
        --providers libaudiowrt-alsa-minimal > "$out"
    grep -q '^libaudiowrt-alsa-minimal|' "$out"
    grep -q '^libaudiowrt-player|' "$out"
    grep -q "^${player}|" "$out"
done



python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-core audiowrt-extensions audiowrt-spotify > "$tmp/spotify"
grep -q '^librespot|' "$tmp/spotify"
grep -q '^audiowrt-spotify|' "$tmp/spotify"
if grep -Eq '^(audiowrt-bluetooth|bluez-alsa|audiowrt-bluez|audiowrt-btctl)\|' "$tmp/spotify"; then
    echo "ERROR: Spotify build selected Bluetooth packages." >&2
    exit 1
fi

# The Bluetooth root includes the BlueZ package that carries A2DP/AVRCP; the
# minimal ALSA and Bluetooth kernel packages are part of
# the AudioWRT-owned dependency closure.
python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-core audiowrt-extensions libaudiowrt-alsa-minimal kmod-audiowrt-bluetooth \
    kmod-audiowrt-sound-core kmod-audiowrt-usb-audio audiowrt-bluetooth > "$tmp/bluetooth"
for package in libaudiowrt-alsa-minimal audiowrt-sbc audiowrt-bluez audiowrt-btctl bluez-alsa kmod-audiowrt-bluetooth audiowrt-bluetooth; do
    grep -q "^${package}|" "$tmp/bluetooth"
done
for package in kmod-audiowrt-sound-core kmod-audiowrt-usb-audio; do
    grep -q "^${package}|" "$tmp/bluetooth"
done
if grep -Eq '^(audiowrt-spotify|librespot)\|' "$tmp/bluetooth"; then
    echo "ERROR: Bluetooth baseline selected Spotify packages." >&2
    exit 1
fi

# A single BlueZ source target must not inherit the unrelated profile roots.
python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-bluez \
    --providers audiowrt-sbc audiowrt-bluez audiowrt-btctl bluez-alsa audiowrt-bluetooth kmod-audiowrt-bluetooth > "$tmp/bluez-target"
grep -q '^audiowrt-bluez|' "$tmp/bluez-target"
if grep -Eq '^(audiowrt-sbc|audiowrt-btctl|bluez-alsa|audiowrt-bluetooth|kmod-audiowrt-bluetooth)\|' "$tmp/bluez-target"; then
    echo "ERROR: compiling the audiowrt-bluez target selected unrelated AudioWRT targets." >&2
    cat "$tmp/bluez-target" >&2
    exit 1
fi

python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    bluez-alsa \
    --providers audiowrt-sbc audiowrt-bluez audiowrt-btctl bluez-alsa audiowrt-bluetooth kmod-audiowrt-bluetooth > "$tmp/bluez-alsa-target"
grep -q '^audiowrt-bluez|' "$tmp/bluez-alsa-target"
grep -q '^audiowrt-sbc|' "$tmp/bluez-alsa-target"
if grep -Eq '^(audiowrt-btctl|audiowrt-bluetooth|kmod-audiowrt-bluetooth)\|' "$tmp/bluez-alsa-target"; then
    echo "ERROR: compiling bluez-alsa selected unrelated AudioWRT targets." >&2
    cat "$tmp/bluez-alsa-target" >&2
    exit 1
fi

printf 'Package build selection tests passed.\n'
