#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_script="$repo_root/scripts/build.sh"

if grep -Fq 'download_file "$feeds_buildinfo_url" "$sdk_dir/feeds.conf"' "$build_script"; then
    echo "ERROR: feeds.buildinfo must not replace the SDK feed configuration." >&2
    exit 1
fi

grep -Fq 'cp "$sdk_dir/feeds.conf.default" "$sdk_dir/feeds.conf"' "$build_script" || {
    echo "ERROR: build.sh must start from the official SDK feeds.conf.default." >&2
    exit 1
}

grep -Fq "src-git([[:space:]]+--root=package)?[[:space:]]+base" "$build_script" || {
    echo "ERROR: build.sh must validate that the SDK base source feed is present." >&2
    exit 1
}

grep -Fq 'download_file "$feeds_buildinfo_url" "$official_feeds_buildinfo"' "$build_script" || {
    echo "ERROR: official feeds.buildinfo must be retained separately as provenance." >&2
    exit 1
}

grep -Fq 'cp "$sdk_dir/feeds.conf" "$output_dir/sdk-feeds.conf"' "$build_script" || {
    echo "ERROR: resolved SDK feed configuration must be included in build artifacts." >&2
    exit 1
}

grep -Fq 'cp "$official_feeds_buildinfo" "$output_dir/official-feeds.buildinfo"' "$build_script" || {
    echo "ERROR: official feeds.buildinfo provenance must be included in build artifacts." >&2
    exit 1
}

printf 'SDK feed configuration test passed.\n'
