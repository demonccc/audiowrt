#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 "$repo_root/scripts/resolve-features.py" "$repo_root/config/features.map" "" > "$tmp/none.json"
python3 - "$tmp/none.json" <<'PY'
import json, sys
obj = json.load(open(sys.argv[1]))
assert obj["features"] == []
assert obj["packages"] == []
PY

python3 "$repo_root/scripts/resolve-features.py" "$repo_root/config/features.map" "mpd,airplay" > "$tmp/selected.json"
python3 - "$tmp/selected.json" <<'PY'
import json, sys
obj = json.load(open(sys.argv[1]))
assert [x["id"] for x in obj["features"]] == ["mpd", "airplay"]
assert obj["packages"] == ["audiowrt-mpd", "audiowrt-airplay"]
PY

python3 "$repo_root/scripts/resolve-features.py" "$repo_root/config/features.map" "all" > "$tmp/all.json"
cmp -s "$tmp/selected.json" "$tmp/all.json" || {
    # requested differs by design; compare the resolved selections only.
    python3 - "$tmp/selected.json" "$tmp/all.json" <<'PY'
import json, sys
left = json.load(open(sys.argv[1]))
right = json.load(open(sys.argv[2]))
assert left["features"] == right["features"]
assert left["packages"] == right["packages"]
PY
}

if python3 "$repo_root/scripts/resolve-features.py" "$repo_root/config/features.map" "does-not-exist" >/dev/null 2>&1; then
    echo "ERROR: unknown feature unexpectedly succeeded" >&2
    exit 1
fi

printf 'Feature resolution tests passed.\n'
