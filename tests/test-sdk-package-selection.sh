#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_script="$repo_root/scripts/build.sh"

grep -Fq 'package_config_args+=("CONFIG_PACKAGE_${package}=m")' "$build_script"
grep -Fq '"${package_config_args[@]}" "${download_targets[@]}" NO_DEPS=1' "$build_script"
grep -Fq '"${package_config_args[@]}" "$target_path" NO_DEPS=1' "$build_script"
grep -Fq '"${package_config_args[@]}" "$target_path" -j"$jobs"' "$build_script"
grep -Fq 'OpenWrt still writes the original DEPENDS metadata into the APK' "$build_script"

if grep -Eq 'feeds install.*(build_packages|audio_feed_roots)' "$build_script"; then
    echo "ERROR: selected package runtime dependencies must not be recursively installed as Kconfig sources." >&2
    exit 1
fi
if grep -Fq 'include/config/auto.conf' "$build_script"; then
    echo "ERROR: package selection must not depend on Kconfig retaining missing runtime dependency symbols." >&2
    exit 1
fi

printf 'SDK passes selected AudioWRT symbols directly to download and compile targets.\n'
