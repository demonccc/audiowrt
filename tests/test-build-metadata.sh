#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/targetinfo" <<'EOF'
Target: mediatek/filogic
Default-Packages: base-files netifd
@@
Target-Profile: DEVICE_glinet_gl-mt6000
Target-Profile-Name: GL.iNet GL-MT6000
Target-Profile-Packages: kmod-usb3 kmod-mt7915e
@@
Target-Profile: DEVICE_example-no-usb
Target-Profile-Name: Example Device Without USB
Target-Profile-Packages: kmod-example
@@
EOF

python3 "$repo_root/scripts/resolve-platform.py" \
    "$tmp_dir/targetinfo" \
    glinet_gl-mt6000 > "$tmp_dir/platform.json"

python3 - "$tmp_dir/platform.json" <<'PY'
import json
import sys

metadata = json.load(open(sys.argv[1], encoding="utf-8"))
assert metadata["target"] == "mediatek"
assert metadata["subtarget"] == "filogic"
assert metadata["platform"] == "glinet_gl-mt6000"
assert "kmod-usb3" in metadata["profile_packages"]
PY

python3 "$repo_root/scripts/check-usb.py" \
    "$tmp_dir/platform.json" \
    "$repo_root/config/usb-host-packages"

python3 "$repo_root/scripts/resolve-platform.py" \
    "$tmp_dir/targetinfo" \
    example-no-usb > "$tmp_dir/no-usb.json"

if python3 "$repo_root/scripts/check-usb.py" \
    "$tmp_dir/no-usb.json" \
    "$repo_root/config/usb-host-packages"; then
    echo "ERROR: USB validation should have rejected example-no-usb." >&2
    exit 1
fi

echo "Build metadata tests passed."
