#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/targets" <<'EOF'
audiowrt-core|package/audiowrt/audiowrt-core/compile
audiowrt-audio|package/feeds/audiowrt/audiowrt-audio/compile
audiowrt-extensions|package/feeds/audiowrt/audiowrt-extensions/compile
audiowrt-spotify|package/feeds/audiowrt/audiowrt-spotify/compile
librespot|package/feeds/audiowrt/librespot/compile
audiowrt-bluetooth|package/feeds/audiowrt/audiowrt-bluetooth/compile
bluez-alsa|package/feeds/audiowrt/bluez-alsa/compile
EOF

cat > "$tmp/packageinfo" <<'EOF'
Package: audiowrt-core
Depends: +libc +audiowrt-audio
Package: audiowrt-audio
Depends: +uci
Package: audiowrt-extensions
Depends: +audiowrt-audio +apk-mbedtls
Package: audiowrt-spotify
Depends: +audiowrt-extensions +librespot
Package: librespot
Depends: +alsa-lib
Package: audiowrt-bluetooth
Depends: +audiowrt-extensions +bluez-alsa +kmod-btusb
Package: bluez-alsa
Depends: +alsa-lib
EOF

resolver="$repo_root/scripts/resolve-package-build-targets.py"

python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-core audiowrt-extensions > "$tmp/core"

grep -q '^audiowrt-audio|' "$tmp/core"
grep -q '^audiowrt-core|' "$tmp/core"
grep -q '^audiowrt-extensions|' "$tmp/core"
if grep -Eq '^(audiowrt-spotify|librespot|audiowrt-bluetooth|bluez-alsa)\|' "$tmp/core"; then
    echo "ERROR: core-only build selected optional AudioWRT engines." >&2
    cat "$tmp/core" >&2
    exit 1
fi

python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-core audiowrt-extensions audiowrt-spotify > "$tmp/spotify"
grep -q '^librespot|' "$tmp/spotify"
grep -q '^audiowrt-spotify|' "$tmp/spotify"
if grep -Eq '^(audiowrt-bluetooth|bluez-alsa)\|' "$tmp/spotify"; then
    echo "ERROR: Spotify build selected Bluetooth packages." >&2
    exit 1
fi

python3 "$resolver" "$tmp/targets" "$tmp/packageinfo" \
    audiowrt-core audiowrt-extensions audiowrt-bluetooth > "$tmp/bluetooth"
grep -q '^bluez-alsa|' "$tmp/bluetooth"
grep -q '^audiowrt-bluetooth|' "$tmp/bluetooth"
if grep -Eq '^(audiowrt-spotify|librespot)\|' "$tmp/bluetooth"; then
    echo "ERROR: Bluetooth build selected Spotify packages." >&2
    exit 1
fi

printf 'Package build selection tests passed.\n'
