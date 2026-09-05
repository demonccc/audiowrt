#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "ERROR: usage: configure-openwrt.sh <openwrt-dir> <platform.json> <packages.add> <packages.remove>" >&2
    exit 2
fi

openwrt_dir="$1"
metadata_file="$2"
packages_add="$3"
packages_remove="$4"

json_value() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]])' "$metadata_file" "$1"
}

read_package_list() {
    grep -Ev '^[[:space:]]*(#|$)' "$1" || true
}

set_config_y() {
    local symbol="$1"
    sed -i -E "/^(# )?CONFIG_${symbol}(=| is not set)/d" .config
    printf 'CONFIG_%s=y\n' "$symbol" >> .config
}

set_config_n() {
    local symbol="$1"
    sed -i -E "/^(# )?CONFIG_${symbol}(=| is not set)/d" .config
    printf '# CONFIG_%s is not set\n' "$symbol" >> .config
}

target="$(json_value target)"
subtarget="$(json_value subtarget)"
platform="$(json_value platform)"

cd "$openwrt_dir"

cat > .config <<EOF
CONFIG_TARGET_${target}=y
CONFIG_TARGET_${target}_${subtarget}=y
CONFIG_TARGET_${target}_${subtarget}_DEVICE_${platform}=y
EOF

make defconfig

expected_device="CONFIG_TARGET_${target}_${subtarget}_DEVICE_${platform}=y"
if ! grep -Fqx "$expected_device" .config; then
    echo "ERROR: OpenWrt did not accept the requested device profile." >&2
    echo "Expected configuration: $expected_device" >&2
    exit 4
fi

while IFS= read -r package; do
    set_config_y "PACKAGE_${package}"
done < <(read_package_list "$packages_add")

while IFS= read -r package; do
    set_config_n "PACKAGE_${package}"
done < <(read_package_list "$packages_remove")

make defconfig

failed=0

while IFS= read -r package; do
    symbol="CONFIG_PACKAGE_${package}=y"
    if ! grep -Fqx "$symbol" .config; then
        echo "ERROR: required AudioWRT package was not enabled: $package" >&2
        failed=1
    fi
done < <(read_package_list "$packages_add")

while IFS= read -r package; do
    if grep -Eq "^CONFIG_PACKAGE_${package}=(y|m)$" .config; then
        echo "ERROR: forbidden router package is still selected: $package" >&2
        failed=1
    fi
done < <(read_package_list "$packages_remove")

if [[ "$failed" -ne 0 ]]; then
    echo "ERROR: AudioWRT package policy validation failed." >&2
    exit 5
fi

printf 'Configured OpenWrt target %s/%s with profile %s\n' "$target" "$subtarget" "$platform"
