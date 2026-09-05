#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="${PLATFORM:-}"
requested_ref="${OPENWRT_REF:-stable}"
openwrt_repo="${OPENWRT_REPOSITORY:-https://github.com/openwrt/openwrt.git}"
packages_repo="${AUDIOWRT_PACKAGES_REPOSITORY:-https://github.com/demonccc/audiowrt-packages.git}"
packages_ref="${AUDIOWRT_PACKAGES_REF:-main}"
jobs="${JOBS:-}"

if [[ -z "$platform" ]]; then
    echo "ERROR: PLATFORM is required." >&2
    exit 2
fi

if [[ -z "$jobs" ]]; then
    jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
fi

resolved_ref="$(OPENWRT_REPOSITORY="$openwrt_repo" bash "$repo_root/scripts/resolve-openwrt-ref.sh" "$requested_ref")"
safe_ref="$(printf '%s' "$resolved_ref" | tr '/:@ ' '____')"
work_dir="$repo_root/.work/${platform}-${safe_ref}"
openwrt_dir="$work_dir/openwrt"
platform_metadata="$work_dir/platform.json"
output_dir="$repo_root/output/$platform/$safe_ref"

printf 'AudioWRT build\n'
printf '  Platform: %s\n' "$platform"
printf '  Requested OpenWrt ref: %s\n' "$requested_ref"
printf '  Resolved OpenWrt ref: %s\n' "$resolved_ref"
printf '  AudioWRT packages ref: %s\n' "$packages_ref"
printf '  Jobs: %s\n' "$jobs"

rm -rf "$work_dir" "$output_dir"
mkdir -p "$work_dir" "$output_dir"

echo "Cloning OpenWrt..."
git clone --depth=1 --filter=blob:none --no-checkout "$openwrt_repo" "$openwrt_dir"
git -C "$openwrt_dir" fetch --depth=1 origin "$resolved_ref"
git -C "$openwrt_dir" checkout --detach FETCH_HEAD

cd "$openwrt_dir"
cp feeds.conf.default feeds.conf

feed_source="$packages_repo"
if [[ -n "$packages_ref" && "$packages_ref" != "main" ]]; then
    feed_source="${feed_source};${packages_ref}"
fi

if ! grep -qE '^src-git[[:space:]]+audiowrt[[:space:]]' feeds.conf; then
    printf '\nsrc-git audiowrt %s\n' "$feed_source" >> feeds.conf
fi

./scripts/feeds update -a
./scripts/feeds install -a

# Build OpenWrt's own metadata before AudioWRT selects or adds packages.
make -s prepare-tmpinfo

python3 "$repo_root/scripts/resolve-platform.py" \
    "$openwrt_dir/tmp/.targetinfo" \
    "$platform" > "$platform_metadata"

python3 "$repo_root/scripts/check-usb.py" \
    "$platform_metadata" \
    "$repo_root/config/usb-host-packages"

bash "$repo_root/scripts/configure-openwrt.sh" \
    "$openwrt_dir" \
    "$platform_metadata" \
    "$repo_root/config/packages.add" \
    "$repo_root/config/packages.remove"

mkdir -p "$openwrt_dir/files"
rsync -a "$repo_root/files/" "$openwrt_dir/files/"

target="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["target"])' "$platform_metadata")"
subtarget="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["subtarget"])' "$platform_metadata")"

printf 'Building OpenWrt for %s/%s...\n' "$target" "$subtarget"
if ! make -j"$jobs"; then
    echo "ERROR: OpenWrt build failed." >&2
    echo "For detailed diagnostics, rerun inside $openwrt_dir with: make -j1 V=s" >&2
    exit 10
fi

artifact_dir="$openwrt_dir/bin/targets/$target/$subtarget"
if [[ ! -d "$artifact_dir" ]]; then
    echo "ERROR: expected OpenWrt artifact directory was not produced: $artifact_dir" >&2
    exit 11
fi

rsync -a "$artifact_dir/" "$output_dir/"
cp "$platform_metadata" "$output_dir/platform.json"
cp "$repo_root/config/packages.add" "$output_dir/audiowrt-packages.add"
cp "$repo_root/config/packages.remove" "$output_dir/audiowrt-packages.remove"
cp "$openwrt_dir/.config" "$output_dir/openwrt.config"

openwrt_commit="$(git -C "$openwrt_dir" rev-parse HEAD)"
audiowrt_commit="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf 'unknown')"
audiowrt_packages_commit="$(git -C "$openwrt_dir/feeds/audiowrt" rev-parse HEAD 2>/dev/null || printf 'unknown')"

python3 - "$platform_metadata" "$output_dir/manifest.json" <<PY
import json
import sys

metadata = json.load(open(sys.argv[1], encoding="utf-8"))
manifest = {
    "audiowrt_commit": "$audiowrt_commit",
    "audiowrt_packages_repository": "$packages_repo",
    "audiowrt_packages_ref": "$packages_ref",
    "audiowrt_packages_commit": "$audiowrt_packages_commit",
    "openwrt_repository": "$openwrt_repo",
    "openwrt_requested_ref": "$requested_ref",
    "openwrt_resolved_ref": "$resolved_ref",
    "openwrt_commit": "$openwrt_commit",
    "platform": metadata,
}
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

printf '\nAudioWRT build complete.\nArtifacts: %s\n' "$output_dir"
