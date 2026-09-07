#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$repo_root/scripts/resolve-openwrt-ref.sh"

[[ "$(bash "$resolver" 25.12.5)" == "v25.12.5" ]]
[[ "$(bash "$resolver" v25.12.5)" == "v25.12.5" ]]
[[ "$(bash "$resolver")" == "v25.12.5" ]]

for invalid in stable openwrt-25.12 main master snapshot v25.12.5-rc1 25.12; do
    if bash "$resolver" "$invalid" >/dev/null 2>&1; then
        echo "ERROR: invalid release unexpectedly accepted: $invalid" >&2
        exit 1
    fi
done

printf 'Exact-release validation tests passed.\n'
