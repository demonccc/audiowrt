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

if grep -Fq './scripts/feeds install -a' "$build_script"; then
    echo "ERROR: SDK setup must not install every package from every feed." >&2
    exit 1
fi

grep -Fq './scripts/feeds install "${feed_install_packages[@]}"' "$build_script" || {
    echo "ERROR: build.sh must install only the requested feed packages." >&2
    exit 1
}

grep -Fq '[[ "$local_target" == package/audiowrt/* ]] && continue' "$build_script" || {
    echo "ERROR: distribution-only packages must be excluded from feeds install." >&2
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

grep -Fq 'sdk-feed-install-packages.txt' "$build_script" || {
    echo "ERROR: selected SDK feed packages must be recorded in build artifacts." >&2
    exit 1
}

printf 'SDK feed configuration test passed.\n'
