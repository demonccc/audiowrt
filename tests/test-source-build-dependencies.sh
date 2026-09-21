#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/targets" <<'EOF'
libaudiowrt-alsa-minimal|package/feeds/audiowrt/libaudiowrt-alsa-minimal/compile
audiowrt-wpad|package/feeds/audiowrt/audiowrt-wpad/compile
audiowrt-spotify|package/feeds/audiowrt/audiowrt-spotify/compile
librespot|package/feeds/audiowrt/librespot/compile
audiowrt-sbc|package/feeds/audiowrt/audiowrt-sbc/compile
audiowrt-bluez|package/feeds/audiowrt/audiowrt-bluez/compile
audiowrt-btctl|package/feeds/audiowrt/audiowrt-btctl/compile
bluez-alsa|package/feeds/audiowrt/bluez-alsa/compile
audiowrt-bluetooth|package/feeds/audiowrt/audiowrt-bluetooth/compile
EOF

cat > "$tmp/packageinfo" <<'EOF'
Build-Depends: rust/host
Package: librespot
Depends: +libc +alsa-lib +audiowrt-spotify +kmod-sound-core
Package: libaudiowrt-alsa-minimal
Depends: +kmod-sound-core +libpthread +librt
Provides: alsa-lib
Package: audiowrt-wpad
Depends: +libnl-tiny +hostapd-common +libubus +libblobmsg-json +libudebug +libmbedtls
Provides: hostapd wpa-supplicant
Package: audiowrt-spotify
Depends: +librespot
Package: audiowrt-sbc
Depends: +libc
Package: audiowrt-bluez
Depends: +bluez-libs +glib2 +dbus +alsa-lib
Package: audiowrt-btctl
Depends: +glib2
Build-Depends: glib2/host
Package: bluez-alsa
Depends: +libc +alsa-lib +audiowrt-bluez +bluez-libs +glib2 +audiowrt-sbc +dbus
Package: audiowrt-bluetooth
Depends: +audiowrt-bluez +audiowrt-btctl +bluez-alsa +kmod-btusb
EOF

resolver="$repo_root/scripts/resolve-source-build-dependencies.py"
python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" librespot \
    --providers libaudiowrt-alsa-minimal audiowrt-spotify librespot > "$tmp/librespot"

grep -qx 'rust' "$tmp/librespot"
if grep -qx 'alsa-lib' "$tmp/librespot"; then
    echo 'ERROR: selected AudioWRT provider did not satisfy the alsa-lib build dependency.' >&2
    exit 1
fi
if grep -Eq '^(libc|audiowrt-spotify|libaudiowrt-alsa-minimal|kernel|kmod-)' "$tmp/librespot"; then
    echo "ERROR: toolchain or AudioWRT-owned dependencies leaked into source dependency roots." >&2
    cat "$tmp/librespot" >&2
    exit 1
fi


# audiowrt-btctl is native AudioWRT C code, but it includes GIO/GLib headers.
# A standalone btctl build must therefore stage glib2 before compiling btctl.
python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" audiowrt-btctl \
    --providers audiowrt-btctl > "$tmp/btctl"
grep -qx 'glib2' "$tmp/btctl"
if grep -Eq '^(audiowrt-btctl|kernel|kmod-)' "$tmp/btctl"; then
    echo 'ERROR: standalone btctl development dependency resolution leaked owned/runtime packages.' >&2
    cat "$tmp/btctl" >&2
    exit 1
fi

python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-bluez bluez-alsa \
    --providers libaudiowrt-alsa-minimal audiowrt-sbc audiowrt-bluez audiowrt-btctl bluez-alsa audiowrt-bluetooth > "$tmp/bluetooth"
for package in glib2 dbus bluez-libs; do
    grep -qx "$package" "$tmp/bluetooth"
done
if grep -qx 'alsa-lib' "$tmp/bluetooth"; then
    echo 'ERROR: minimal ALSA provider leaked the official ALSA source dependency.' >&2
    exit 1
fi
if grep -Eq '^(libc|audiowrt-sbc|audiowrt-bluez|audiowrt-btctl|bluez-daemon|sbc|libsndfile|libical|libreadline|libncurses)$' "$tmp/bluetooth"; then
    echo "ERROR: generic or AudioWRT-owned dependencies leaked into Bluetooth source roots." >&2
    cat "$tmp/bluetooth" >&2
    exit 1
fi

# Runtime kernel packages must not trigger kernel source compilation while
# staging userspace dependencies.
if grep -Eq '^(kernel|kmod-)' "$tmp/bluetooth"; then
    echo 'ERROR: runtime kernel packages leaked into userspace source dependencies.' >&2
    cat "$tmp/bluetooth" >&2
    exit 1
fi

# Standard/full profiles still use AudioWRT SBC, while ALSA remains official.
python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-bluez bluez-alsa \
    --providers audiowrt-sbc audiowrt-bluez audiowrt-btctl bluez-alsa audiowrt-bluetooth > "$tmp/official-bluetooth"
grep -qx 'alsa-lib' "$tmp/official-bluetooth"
if grep -Eq '^(sbc|libsndfile|audiowrt-sbc)$' "$tmp/official-bluetooth"; then
    echo 'ERROR: standard Bluetooth source roots bypassed the AudioWRT SBC provider.' >&2
    exit 1
fi

printf 'Source build dependency tests passed.\n'
