#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_script="$repo_root/scripts/build.sh"

if grep -Fq 'make_run "$sdk_dir" package/download' "$build_script"; then
    echo "ERROR: build.sh must not invoke the SDK-wide package/download target." >&2
    exit 1
fi

grep -Fq 'download_target="${target_path%/compile}/download"' "$build_script" || {
    echo "ERROR: build.sh does not derive per-package download targets." >&2
    exit 1
}

grep -Fq 'make_run "$sdk_dir" "$download_target" -j"$jobs"' "$build_script" || {
    echo "ERROR: build.sh does not execute selected package download targets." >&2
    exit 1
}

printf 'SDK download scope test passed.\n'
