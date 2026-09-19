#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

dry_run="$(make -n packages \
    AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5 \
    PACKAGE=audiowrt-player-flac \
    AUDIOWRT_PACKAGES_REF=fix/provisioning-runtime)"

grep -q 'AUDIOWRT_BUILD_MODE="packages"' <<<"$dry_run"
grep -q 'AUDIOWRT_PACKAGE="audiowrt-player-flac"' <<<"$dry_run"
grep -q 'bash scripts/run-in-docker.sh' <<<"$dry_run"

grep -q 'AUDIOWRT_BUILD_MODE="${AUDIOWRT_BUILD_MODE:-firmware}"' scripts/run-in-docker.sh
grep -q 'AUDIOWRT_PACKAGE="${AUDIOWRT_PACKAGE:-all}"' scripts/run-in-docker.sh

grep -q 'build_mode="${AUDIOWRT_BUILD_MODE:-firmware}"' scripts/build.sh
grep -q 'package_request="${AUDIOWRT_PACKAGE:-all}"' scripts/build.sh
grep -q 'BUILD_MODE=exact-release-sdk-packages' scripts/build.sh
grep -q 'output/packages' scripts/build.sh
grep -q 'unknown AudioWRT package' scripts/build.sh

workflow=.github/workflows/build-packages.yml
[[ -f "$workflow" ]]
grep -q '^name: Build AudioWRT Packages$' "$workflow"
grep -q '^      package:$' "$workflow"
grep -q "default: all" "$workflow"
grep -q 'make packages' "$workflow"
grep -q "PACKAGE='\${{ inputs.package }}'" "$workflow"
grep -q 'path: output/' "$workflow"

echo "Package-only build mode contract OK"
