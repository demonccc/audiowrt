#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/targets" <<'EOF'
audiowrt-spotify|package/feeds/audiowrt/audiowrt-spotify/compile
librespot|package/feeds/audiowrt/librespot/compile
audiowrt-bluetooth|package/feeds/audiowrt/audiowrt-bluetooth/compile
bluez-alsa|package/feeds/audiowrt/bluez-alsa/compile
EOF

cat > "$tmp/packageinfo" <<'EOF'
Build-Depends: rust/host
Package: librespot
Depends: +libc +alsa-lib +audiowrt-spotify
Package: audiowrt-spotify
Depends: +librespot
Package: bluez-alsa
Depends: +libc +alsa-lib +bluez-daemon +glib2 +sbc +dbus +audiowrt-bluetooth
Package: audiowrt-bluetooth
Depends: +bluez-alsa
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

python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" bluez-alsa > "$tmp/bluez"
for package in alsa-lib bluez-daemon glib2 sbc dbus; do
    grep -qx "$package" "$tmp/bluez"
done
if grep -Eq '^(libc|audiowrt-bluetooth)$' "$tmp/bluez"; then
    echo "ERROR: toolchain or AudioWRT-owned dependencies leaked into BlueALSA dependency roots." >&2
    exit 1
fi

printf 'Source build dependency tests passed.\n'
