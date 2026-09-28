#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$repo_root/scripts/resolve-openwrt-ref.sh"

[[ "$(bash "$resolver" 1.2.3)" == "v1.2.3" ]]
[[ "$(bash "$resolver" v9.8.7)" == "v9.8.7" ]]

for invalid in stable main master snapshot v1.2.3-rc1 1.2 release-1.2.3; do
    if bash "$resolver" "$invalid" >/dev/null 2>&1; then
        echo "ERROR: invalid release unexpectedly accepted: $invalid" >&2
        exit 1
    fi
done

printf 'Exact-release format contract passed.\n'
