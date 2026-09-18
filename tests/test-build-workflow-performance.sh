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


echo "Build workflow performance safeguards passed."
