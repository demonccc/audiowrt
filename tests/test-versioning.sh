#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "ERROR: VERSION must use MAJOR.MINOR.PATCH semantic versioning." >&2
    exit 1
}

grep -Fq 'AUDIOWRT_VERSION=$audiowrt_version' "$repo_root/scripts/build.sh"
grep -Fq '"audiowrt_version": "$audiowrt_version"' "$repo_root/scripts/build.sh"

echo "AudioWRT distribution version contract OK: $version"
