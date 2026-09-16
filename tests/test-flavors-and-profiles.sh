#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$repo_root/scripts/resolve-audiowrt-profile.py"
flavors="$repo_root/config/flavors"

for fragment in common minimal; do
    test -s "$flavors/$fragment.yaml"
done

selectable_flavors=(
    minimal-usb-audio
    minimal-usb-bluetooth
    minimal-usb-audio-bluetooth
    usb-audio
    usb-bluetooth
    usb-audio-bluetooth
)
for flavor in "${selectable_flavors[@]}"; do
    test -s "$flavors/$flavor.yaml"
done

# The old directory-based flavor model must not coexist with the YAML model.
if find "$flavors" -mindepth 2 -type f \( -name packages.add -o -name packages.remove \) | grep -q .; then
    echo 'ERROR: legacy flavor package files still exist.' >&2
    exit 1
fi

# Global package policy belongs to common.
grep -q '^  - audiowrt-udhcpd$' "$flavors/common.yaml"
grep -q '^  - dnsmasq$' "$flavors/common.yaml"
grep -q '^  - busybox$' "$flavors/common.yaml"

# Minimal flavors inherit both common policy and the minimal runtime policy.
for flavor in minimal-usb-audio minimal-usb-bluetooth; do
    grep -q '^  - common$' "$flavors/$flavor.yaml"
    grep -q '^  - minimal$' "$flavors/$flavor.yaml"
done
grep -q '^  - minimal-usb-audio$' "$flavors/minimal-usb-audio-bluetooth.yaml"
grep -q '^  - minimal-usb-bluetooth$' "$flavors/minimal-usb-audio-bluetooth.yaml"
grep -q '^  - usb-audio$' "$flavors/usb-audio-bluetooth.yaml"
grep -q '^  - usb-bluetooth$' "$flavors/usb-audio-bluetooth.yaml"

# Every real profile must resolve to one of the six selectable canonical flavors.
for profile_file in "$repo_root"/profiles/*.yaml; do
    profile="$(basename "$profile_file" .yaml)"
    resolved="$(python3 "$resolver" "$repo_root/profiles" "$flavors" "$profile")"
    python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["id"] == sys.argv[1]
assert data["flavor"] in {
    "minimal-usb-audio", "minimal-usb-bluetooth", "minimal-usb-audio-bluetooth",
    "usb-audio", "usb-bluetooth", "usb-audio-bluetooth",
}
assert data["openwrt_source"] in {"release", "snapshot"}
assert not set(data["packages_add"]) & set(data["packages_remove"])
assert "audiowrt-udhcpd" in data["packages_add"]
assert "dnsmasq" in data["packages_remove"]
' "$profile" <<< "$resolved"
done

wdr="$(python3 "$resolver" "$repo_root/profiles" "$flavors" tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5)"
python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["flavor"] == "minimal-usb-bluetooth"
assert data["openwrt_profile"] == "tplink_tl-wdr4300-v1"
assert data["squashfs_block_size"] == "1024"
assert {"audiowrt-minimal-alsa", "audiowrt-minimal-mbedtls", "kmod-audiowrt-bluetooth"} <= set(data["packages_add"])
assert {"alsa-lib", "dnsmasq", "kmod-bluetooth", "kmod-usb-audio"} <= set(data["packages_remove"])
' <<< "$wdr"

# Legacy profile names remain accepted, but resolve to the canonical audio-before-bluetooth name.
legacy_profile="$(find "$repo_root/profiles" -maxdepth 1 -name '*-usb-bluetooth-audio-*.yaml' | head -n1 || true)"
if [[ -n "$legacy_profile" ]]; then
    legacy_id="$(basename "$legacy_profile" .yaml)"
    resolved="$(python3 "$resolver" "$repo_root/profiles" "$flavors" "$legacy_id")"
    python3 -c 'import json,sys; assert json.load(sys.stdin)["flavor"] == "usb-audio-bluetooth"' <<< "$resolved"
fi

# Validate inherited conflict handling with synthetic flavors.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/flavors" "$tmp/profiles"
cat > "$tmp/flavors/parent-add.yaml" <<'EOF'
schema_version: 1
include: []
packages_add:
  - conflict-package
packages_remove: []
EOF
cat > "$tmp/flavors/parent-remove.yaml" <<'EOF'
schema_version: 1
include: []
packages_add: []
packages_remove:
  - conflict-package
EOF
cat > "$tmp/flavors/conflict.yaml" <<'EOF'
schema_version: 1
include:
  - parent-add
  - parent-remove
packages_add: []
packages_remove: []
EOF
cat > "$tmp/flavors/resolved.yaml" <<'EOF'
schema_version: 1
include:
  - parent-add
  - parent-remove
packages_add:
  - conflict-package
packages_remove: []
EOF
cat > "$tmp/flavors/cycle-a.yaml" <<'EOF'
schema_version: 1
include:
  - cycle-b
packages_add: []
packages_remove: []
EOF
cat > "$tmp/flavors/cycle-b.yaml" <<'EOF'
schema_version: 1
include:
  - cycle-a
packages_add: []
packages_remove: []
EOF

base_profile="$repo_root/profiles/tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5.yaml"
cp "$base_profile" "$tmp/profiles/example-device-conflict-25.12.5.yaml"
cp "$base_profile" "$tmp/profiles/example-device-resolved-25.12.5.yaml"
cp "$base_profile" "$tmp/profiles/example-device-cycle-a-25.12.5.yaml"

if python3 "$resolver" "$tmp/profiles" "$tmp/flavors" example-device-conflict-25.12.5 >/dev/null 2>&1; then
    echo 'ERROR: unresolved inherited package conflict was accepted.' >&2
    exit 1
fi
resolved="$(python3 "$resolver" "$tmp/profiles" "$tmp/flavors" example-device-resolved-25.12.5)"
python3 -c 'import json,sys; d=json.load(sys.stdin); assert "conflict-package" in d["packages_add"]; assert "conflict-package" not in d["packages_remove"]' <<< "$resolved"
if python3 "$resolver" "$tmp/profiles" "$tmp/flavors" example-device-cycle-a-25.12.5 >/dev/null 2>&1; then
    echo 'ERROR: flavor include cycle was accepted.' >&2
    exit 1
fi

grep -q 'AUDIOWRT_PROFILE:-tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5' "$repo_root/scripts/build.sh"
grep -q 'CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=' "$repo_root/scripts/build.sh"

echo 'AudioWRT composable flavor and device profile tests passed.'
