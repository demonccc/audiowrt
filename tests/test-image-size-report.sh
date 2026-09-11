#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/empty" "$tmp/with-image"

if python3 "$repo_root/scripts/image-size-report.py" \
    "$tmp/empty" "$tmp/empty.json" "$tmp/empty.txt" >/dev/null 2>&1; then
    echo "ERROR: empty firmware output unexpectedly succeeded." >&2
    exit 1
fi

grep -q 'No firmware image files were found.' "$tmp/empty.txt"
python3 - "$tmp/empty.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1], encoding='utf-8'))['images'] == []
PY

printf 'firmware' > "$tmp/with-image/openwrt-test-sysupgrade.bin"
python3 "$repo_root/scripts/image-size-report.py" \
    "$tmp/with-image" "$tmp/with-image.json" "$tmp/with-image.txt"

python3 - "$tmp/with-image.json" <<'PY'
import json, sys
images = json.load(open(sys.argv[1], encoding='utf-8'))['images']
assert len(images) == 1
assert images[0]['file'] == 'openwrt-test-sysupgrade.bin'
assert images[0]['bytes'] == 8
PY

grep -q 'openwrt-test-sysupgrade.bin' "$tmp/with-image.txt"
echo 'Image size report tests passed.'
