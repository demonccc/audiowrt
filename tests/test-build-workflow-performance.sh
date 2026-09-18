#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/build-audiowrt.yml"

if grep -Fq 'name: Free disk space' "$workflow"; then
    echo "ERROR: the build workflow must not spend minutes deleting preinstalled runner tools." >&2
    exit 1
fi

grep -Fq 'uses: actions/cache@v4' "$workflow"
grep -Fq "if: \${{ !endsWith(inputs.audiowrt_profile, '-snapshot') }}" "$workflow"
grep -Fq 'path: .cache/audiowrt' "$workflow"
grep -Fq "CACHE_DIR='.cache/audiowrt'" "$workflow"


renderer_smoke="$repo_root/.github/workflows/native-renderer-smoke.yml"
grep -Fq 'AUDIOWRT_PACKAGE_SMOKE=1' "$renderer_smoke" || {
    echo "ERROR: native renderer CI must use package-only smoke mode." >&2
    exit 1
}
grep -Fq 'AUDIOWRT_PACKAGE_SMOKE_PACKAGES="audiowrt-minimal-alsa audiowrt-renderer audiowrt-player-core audiowrt-player-flac audiowrt-player-mp3"' "$renderer_smoke" || {
    echo "ERROR: native renderer CI must compile only the renderer/player package set." >&2
    exit 1
}
if grep -Fq 'Build WDR4300 minimal native renderer image' "$renderer_smoke"; then
    echo "ERROR: native renderer smoke must not build a firmware image." >&2
    exit 1
fi

echo "Build workflow performance safeguards passed."
