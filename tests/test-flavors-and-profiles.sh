#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$repo_root/scripts/resolve-audiowrt-profile.py"
groups="$repo_root/config/package-groups"

for group in \
    common \
    minimal-usb-audio \
    minimal-usb-bluetooth \
    minimal-usb-audio-bluetooth \
    usb-audio \
    usb-bluetooth \
    usb-audio-bluetooth; do
    test -s "$groups/$group.yaml"
done

test ! -e "$groups/minimal.yaml"
test ! -e "$repo_root/config/flavors"

# Global policy belongs to common and common is automatic.
grep -q '^  - audiowrt-branding$' "$groups/common.yaml"
grep -q '^  - audiowrt-udhcpd$' "$groups/common.yaml"
grep -q '^  - dnsmasq$' "$groups/common.yaml"
grep -q '^  - busybox$' "$groups/common.yaml"

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
assert "dnsmasq" in data["packages_remove"]
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
assert {"audiowrt-minimal-alsa", "audiowrt-minimal-mbedtls", "kmod-audiowrt-bluetooth"} <= added
assert {"alsa-lib", "dnsmasq", "kmod-bluetooth", "kmod-usb-audio"} <= removed
' <<< "$wdr_bt"

wdr_audio="$(python3 "$resolver" "$repo_root/profiles" "$groups" tplink-tl-wdr4300-v1-minimal-usb-audio-25.12.5)"
python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["package_groups"] == ["minimal-usb-audio"]
assert data["openwrt_profile"] == "tplink_tl-wdr4300-v1"
added = set(data["packages_add"])
removed = set(data["packages_remove"])
assert {"audiowrt-minimal-alsa", "audiowrt-minimal-mbedtls", "audiowrt-usb-audio", "kmod-usb-audio"} <= added
assert {"dnsmasq", "kmod-bluetooth", "kmod-audiowrt-bluetooth"} <= removed
' <<< "$wdr_audio"

# When a profile intentionally combines groups, later groups win add/remove conflicts.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/groups" "$tmp/profiles"
cat > "$tmp/groups/common.yaml" <<'EOF'
schema_version: 1
packages_add: []
packages_remove: []
EOF
cat > "$tmp/groups/add.yaml" <<'EOF'
schema_version: 1
packages_add:
  - conflict-package
packages_remove: []
EOF
cat > "$tmp/groups/remove.yaml" <<'EOF'
schema_version: 1
packages_add: []
packages_remove:
  - conflict-package
EOF
cat > "$tmp/profiles/example-device-test-25.12.5.yaml" <<'EOF'
schema_version: 1
status: candidate
maintainer_github: demonccc
openwrt_profile: example
target: example
subtarget: generic
package_groups:
  - add
  - remove
packages_add: []
packages_remove: []
EOF
resolved="$(python3 "$resolver" "$tmp/profiles" "$tmp/groups" example-device-test-25.12.5)"
python3 -c 'import json,sys; d=json.load(sys.stdin); assert "conflict-package" not in d["packages_add"]; assert "conflict-package" in d["packages_remove"]' <<< "$resolved"

cat > "$tmp/profiles/example-device-test-25.12.5.yaml" <<'EOF'
schema_version: 1
status: candidate
maintainer_github: demonccc
openwrt_profile: example
target: example
subtarget: generic
package_groups:
  - remove
  - add
packages_add: []
packages_remove: []
EOF
resolved="$(python3 "$resolver" "$tmp/profiles" "$tmp/groups" example-device-test-25.12.5)"
python3 -c 'import json,sys; d=json.load(sys.stdin); assert "conflict-package" in d["packages_add"]; assert "conflict-package" not in d["packages_remove"]' <<< "$resolved"

grep -q 'AUDIOWRT_PROFILE:-tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5' "$repo_root/scripts/build.sh"
grep -q 'CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=' "$repo_root/scripts/build.sh"
grep -q 'config/build/package-build-targets' "$repo_root/scripts/build.sh"
grep -q 'config/build/source-build-packages' "$repo_root/scripts/build.sh"
! grep -q 'check-usb.py' "$repo_root/scripts/build.sh"

echo 'AudioWRT package group and device profile tests passed.'
