#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/targets" <<'EOF'
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
Build-Depends: rust/host
Package: librespot
Depends: +libc +alsa-lib +audiowrt-spotify
Package: audiowrt-spotify
Depends: +librespot
Package: audiowrt-sbc
Depends: +libc
Package: audiowrt-bluez-libs
Depends: +libpthread
Package: audiowrt-bluez
Depends: +audiowrt-bluez-libs +glib2 +dbus +alsa-lib
Package: audiowrt-btctl
Depends: +glib2
Build-Depends: glib2/host
Package: bluez-alsa
Depends: +libc +alsa-lib +audiowrt-bluez +audiowrt-bluez-libs +glib2 +audiowrt-sbc +dbus
Package: audiowrt-bluetooth
Depends: +audiowrt-bluez +audiowrt-btctl +bluez-alsa +kmod-btusb
EOF

resolver="$repo_root/scripts/resolve-source-build-dependencies.py"
python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" librespot > "$tmp/librespot"

grep -qx 'rust' "$tmp/librespot"
grep -qx 'alsa-lib' "$tmp/librespot"
if grep -Eq '^(libc|audiowrt-spotify)$' "$tmp/librespot"; then
    echo "ERROR: toolchain or AudioWRT-owned dependencies leaked into source dependency roots." >&2
    cat "$tmp/librespot" >&2
    exit 1
fi

python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-sbc audiowrt-bluez-libs audiowrt-bluez audiowrt-btctl bluez-alsa > "$tmp/bluetooth"
for package in glib2 dbus alsa-lib; do
    grep -qx "$package" "$tmp/bluetooth"
done
if grep -Eq '^(libc|audiowrt-sbc|audiowrt-bluez-libs|audiowrt-bluez|audiowrt-btctl|bluez-daemon|bluez-libs|sbc|libsndfile|libical|libreadline|libncurses)$' "$tmp/bluetooth"; then
    echo "ERROR: generic or AudioWRT-owned dependencies leaked into Bluetooth source roots." >&2
    cat "$tmp/bluetooth" >&2
    exit 1
fi

# Bluetooth MIDI is part of this measured baseline and relies on ALSA Sequencer.
grep -qx 'alsa-lib' "$tmp/bluetooth"

printf 'Source build dependency tests passed.\n'
