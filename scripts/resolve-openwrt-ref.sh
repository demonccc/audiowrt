#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

requested_release="${1:-25.12.5}"

case "$requested_release" in
    v[0-9]*.[0-9]*.[0-9]*) normalized="$requested_release" ;;
    [0-9]*.[0-9]*.[0-9]*) normalized="v${requested_release}" ;;
    *)
        echo "ERROR: AudioWRT requires an exact final OpenWrt release such as 25.12.5 or v25.12.5." >&2
        echo "Aliases, branches, snapshots and release candidates are not accepted." >&2
        exit 3
        ;;
esac

if ! [[ "$normalized" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: invalid OpenWrt release: $requested_release" >&2
    exit 3
fi

printf '%s\n' "$normalized"
