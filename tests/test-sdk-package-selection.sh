#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

config="$tmp/.config"
cat > "$config" <<'EOF'
CONFIG_PACKAGE_audiowrt-branding=m
# CONFIG_PACKAGE_audiowrt-core is not set
CONFIG_PACKAGE_audiowrt-config=y
CONFIG_PACKAGE_busybox=y
EOF

python3 "$repo_root/scripts/select-sdk-packages.py" "$config" \
    audiowrt-core audiowrt-config

test "$(grep -c '^CONFIG_PACKAGE_audiowrt-core=m$' "$config")" -eq 1
test "$(grep -c '^CONFIG_PACKAGE_audiowrt-config=m$' "$config")" -eq 1
! grep -q '^# CONFIG_PACKAGE_audiowrt-core is not set$' "$config"
! grep -q '^CONFIG_PACKAGE_audiowrt-config=y$' "$config"
grep -q '^CONFIG_PACKAGE_audiowrt-branding=m$' "$config"
grep -q '^CONFIG_PACKAGE_busybox=y$' "$config"

grep -Fq 'select-sdk-packages.py' "$repo_root/scripts/build.sh"
grep -Fq '"${build_packages[@]}"' "$repo_root/scripts/build.sh"
last_defconfig_line="$(grep -n 'make_run "\$sdk_dir" defconfig' "$repo_root/scripts/build.sh" | tail -n 1 | cut -d: -f1)"
selection_line="$(grep -n 'select-sdk-packages.py' "$repo_root/scripts/build.sh" | tail -n 1 | cut -d: -f1)"
test -n "$last_defconfig_line"
test "$selection_line" -gt "$last_defconfig_line"

printf 'SDK selected AudioWRT package symbols survive defconfig pruning.\n'
