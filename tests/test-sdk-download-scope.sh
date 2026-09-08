#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_script="$repo_root/scripts/build.sh"

if grep -Fq 'make_run "$sdk_dir" package/download' "$build_script"; then
    echo "ERROR: build.sh must not invoke the SDK-wide package/download target." >&2
    exit 1
fi

if grep -Fq './scripts/feeds install "${feed_install_packages[@]}"' "$build_script"; then
    echo "ERROR: package-only AudioWRT packages must not recursively install runtime feed dependencies." >&2
    exit 1
fi

grep -Fq './scripts/feeds update packages audiowrt' "$build_script" || {
    echo "ERROR: core builds must update only the package-helper and AudioWRT feeds." >&2
    exit 1
}

grep -Fq 'make_run "$sdk_dir" "${package_only_download_targets[@]}" NO_DEPS=1 -j"$jobs"' "$build_script" || {
    echo "ERROR: package-only download targets must use NO_DEPS=1." >&2
    exit 1
}

grep -Fq 'make_run "$sdk_dir" "${package_only_targets[@]}" NO_DEPS=1 -j"$jobs"' "$build_script" || {
    echo "ERROR: package-only compile targets must use NO_DEPS=1." >&2
    exit 1
}

grep -Fq 'make_run "$sdk_dir" "${source_targets[@]}" -j"$jobs"' "$build_script" || {
    echo "ERROR: genuine AudioWRT source packages must keep normal dependency traversal." >&2
    exit 1
}

grep -Fq 'config/source-build-packages' "$build_script" || {
    echo "ERROR: build.sh must classify genuine source builds explicitly." >&2
    exit 1
}

printf 'SDK package-only build boundary test passed.\n'
