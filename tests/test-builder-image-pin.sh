#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/build-audiowrt.yml"
makefile="$repo_root/Makefile"
runner="$repo_root/scripts/run-in-docker.sh"
build_script="$repo_root/scripts/build.sh"
canonical='demonccc/openwrt-builder:latest'

if grep -Eq '^[[:space:]]*builder_image:' "$workflow" || grep -Fq 'inputs.builder_image' "$workflow"; then
    echo "ERROR: GitHub Actions must not expose the builder image as an input." >&2
    exit 1
fi

if grep -Fq 'BUILDER_IMAGE' "$makefile"; then
    echo "ERROR: Makefile must not expose BUILDER_IMAGE as a build parameter." >&2
    exit 1
fi

grep -Fq "builder_image=\"$canonical\"" "$runner" || {
    echo "ERROR: run-in-docker.sh must pin the canonical builder image." >&2
    exit 1
}

grep -Fq "builder_image=\"$canonical\"" "$build_script" || {
    echo "ERROR: build.sh provenance must use the canonical builder image." >&2
    exit 1
}

if grep -Fq '${BUILDER_IMAGE' "$runner" || grep -Fq '${BUILDER_IMAGE' "$build_script"; then
    echo "ERROR: the canonical builder image must not be overridable through the environment." >&2
    exit 1
fi

printf 'Canonical builder image pin test passed.\n'
