#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_script="$repo_root/scripts/build.sh"

if grep -Fq 'make_run "$sdk_dir" package/download' "$build_script"; then
    echo "ERROR: build.sh must not invoke the SDK-wide package/download target." >&2
    exit 1
fi

grep -Fq 'download_targets+=("${target_path%/compile}/download")' "$build_script" || {
    echo "ERROR: build.sh does not derive the selected download target list." >&2
    exit 1
}

grep -Fq 'make_run "$sdk_dir" "${download_targets[@]}" -j"$jobs"' "$build_script" || {
    echo "ERROR: selected SDK download targets must run in one make invocation." >&2
    exit 1
}

grep -Fq 'make_run "$sdk_dir" "${build_targets[@]}" -j"$jobs"' "$build_script" || {
    echo "ERROR: selected AudioWRT compile targets must run in one make invocation." >&2
    exit 1
}

if grep -Fq 'make_run "$sdk_dir" "$target_path" -j"$jobs"' "$build_script"; then
    echo "ERROR: build.sh must not start a separate make process for every AudioWRT package." >&2
    exit 1
fi

printf 'SDK download/build scope test passed.\n'
