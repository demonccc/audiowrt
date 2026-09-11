#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 "$repo_root/scripts/resolve-features.py" "$repo_root/config/features.map" '' > "$tmp/none.json"
python3 - "$tmp/none.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x['features']==[] and x['packages']==[]
PY
python3 "$repo_root/scripts/resolve-features.py" "$repo_root/config/features.map" 'mpd,airplay,spotify,storage' > "$tmp/selected.json"
python3 - "$tmp/selected.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert [f['id'] for f in x['features']]==['mpd','airplay','spotify','storage']; assert x['packages']==['audiowrt-mpd','audiowrt-airplay','audiowrt-spotify','audiowrt-storage-luci']
PY
python3 "$repo_root/scripts/resolve-features.py" "$repo_root/config/features.map" all > "$tmp/all.json"
python3 - "$tmp/selected.json" "$tmp/all.json" <<'PY'
import json,sys
l=json.load(open(sys.argv[1])); r=json.load(open(sys.argv[2])); assert l['features']==r['features'] and l['packages']==r['packages']
PY
if python3 "$repo_root/scripts/resolve-features.py" "$repo_root/config/features.map" bluetooth >/dev/null 2>&1; then echo 'ERROR: Bluetooth must not be selectable as an optional feature' >&2; exit 1; fi
if python3 "$repo_root/scripts/resolve-features.py" "$repo_root/config/features.map" does-not-exist >/dev/null 2>&1; then echo 'ERROR: unknown feature unexpectedly succeeded' >&2; exit 1; fi
echo 'Feature resolution tests passed.'
