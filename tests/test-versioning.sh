#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "ERROR: VERSION must use MAJOR.MINOR.PATCH semantic versioning." >&2
    exit 1
}

printf 'AudioWRT distribution version format OK: %s\n' "$version"
