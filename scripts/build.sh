#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="${PLATFORM:-}"
requested_ref="${OPENWRT_REF:-stable}"
openwrt_repo="${OPENWRT_REPOSITORY:-https://github.com/openwrt/openwrt.git}"
packages_repo="${AUDIOWRT_PACKAGES_REPOSITORY:-https://github.com/demonccc/audiowrt-packages.git}"
packages_ref="${AUDIOWRT_PACKAGES_REF:-main}"
features="${FEATURES:-}"
jobs="${JOBS:-}"
[ -n "$platform" ] || { echo 'ERROR: PLATFORM is required.' >&2; exit 2; }
[ -n "$jobs" ] || jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
resolved_ref="$(OPENWRT_REPOSITORY="$openwrt_repo" bash "$repo_root/scripts/resolve-openwrt-ref.sh" "$requested_ref")"
safe_ref="$(printf '%s' "$resolved_ref" | tr '/:@ ' '____')"
work_dir="$repo_root/.work/${platform}-${safe_ref}"
openwrt_dir="$work_dir/openwrt"
platform_metadata="$work_dir/platform.json"
selected_features="$work_dir/features.json"
output_dir="$repo_root/output/$platform/$safe_ref"
printf 'AudioWRT build\n  Platform: %s\n  OpenWrt: %s -> %s\n  AudioWRT packages: %s\n  Features: %s\n  Jobs: %s\n' "$platform" "$requested_ref" "$resolved_ref" "$packages_ref" "${features:-none}" "$jobs"
rm -rf "$work_dir" "$output_dir"; mkdir -p "$work_dir" "$output_dir"
git clone --depth=1 --filter=blob:none --no-checkout "$openwrt_repo" "$openwrt_dir"
git -C "$openwrt_dir" fetch --depth=1 origin "$resolved_ref"
git -C "$openwrt_dir" checkout --detach FETCH_HEAD
cd "$openwrt_dir"

# Distribution-only packages live in this repository. Copy them into the clean
# OpenWrt tree before target/package metadata is generated.
mkdir -p "$openwrt_dir/package/audiowrt"
rsync -a "$repo_root/package/" "$openwrt_dir/package/audiowrt/"

cp feeds.conf.default feeds.conf
feed_source="$packages_repo"; if [[ -n "$packages_ref" && "$packages_ref" != 'main' ]]; then feed_source="${feed_source};${packages_ref}"; fi
printf '\nsrc-git audiowrt %s\n' "$feed_source" >> feeds.conf
./scripts/feeds update -a
./scripts/feeds install -a
make -s prepare-tmpinfo
python3 "$repo_root/scripts/resolve-platform.py" "$openwrt_dir/tmp/.targetinfo" "$platform" > "$platform_metadata"
python3 "$repo_root/scripts/check-usb.py" "$platform_metadata" "$repo_root/config/usb-host-packages"
python3 "$repo_root/scripts/resolve-features.py" "$repo_root/config/features.map" "$features" > "$selected_features"
bash "$repo_root/scripts/configure-openwrt.sh" "$openwrt_dir" "$platform_metadata" "$repo_root/config/packages.add" "$repo_root/config/packages.remove" "$selected_features"
mkdir -p "$openwrt_dir/files"; rsync -a "$repo_root/files/" "$openwrt_dir/files/"
target="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["target"])' "$platform_metadata")"
subtarget="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["subtarget"])' "$platform_metadata")"
printf 'Building OpenWrt for %s/%s...\n' "$target" "$subtarget"
if ! make -j"$jobs"; then echo 'ERROR: OpenWrt build failed. The selected image may be too large or another build error occurred.' >&2; echo "Rerun in $openwrt_dir with: make -j1 V=s" >&2; exit 10; fi
artifact_dir="$openwrt_dir/bin/targets/$target/$subtarget"; [ -d "$artifact_dir" ] || { echo "ERROR: artifact directory not produced: $artifact_dir" >&2; exit 11; }
rsync -a "$artifact_dir/" "$output_dir/"
cp "$platform_metadata" "$output_dir/platform.json"; cp "$selected_features" "$output_dir/selected-features.json"; cp "$repo_root/config/packages.add" "$output_dir/audiowrt-packages.add"; cp "$repo_root/config/packages.remove" "$output_dir/audiowrt-packages.remove"; cp "$openwrt_dir/.config" "$output_dir/openwrt.config"
python3 "$repo_root/scripts/image-size-report.py" "$output_dir" "$output_dir/image-size-report.json" "$output_dir/image-size-report.txt"
openwrt_commit="$(git -C "$openwrt_dir" rev-parse HEAD)"; audiowrt_commit="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf unknown)"; audiowrt_packages_commit="$(git -C "$openwrt_dir/feeds/audiowrt" rev-parse HEAD 2>/dev/null || printf unknown)"
python3 - "$platform_metadata" "$selected_features" "$output_dir/manifest.json" <<PY
import json,sys
metadata=json.load(open(sys.argv[1],encoding='utf-8')); features_data=json.load(open(sys.argv[2],encoding='utf-8'))
manifest={'audiowrt_commit':'$audiowrt_commit','audiowrt_packages_repository':'$packages_repo','audiowrt_packages_ref':'$packages_ref','audiowrt_packages_commit':'$audiowrt_packages_commit','openwrt_repository':'$openwrt_repo','openwrt_requested_ref':'$requested_ref','openwrt_resolved_ref':'$resolved_ref','openwrt_commit':'$openwrt_commit','features':features_data['features'],'platform':metadata}
with open(sys.argv[3],'w',encoding='utf-8') as h: json.dump(manifest,h,indent=2,sort_keys=True); h.write('\n')
PY
printf '\nAudioWRT build complete.\nArtifacts: %s\n' "$output_dir"; cat "$output_dir/image-size-report.txt"
