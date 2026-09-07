#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="${PLATFORM:-}"
requested_release="${OPENWRT_RELEASE:-stable}"
openwrt_repo="${OPENWRT_REPOSITORY:-https://github.com/openwrt/openwrt.git}"
packages_repo="${AUDIOWRT_PACKAGES_REPOSITORY:-https://github.com/demonccc/audiowrt-packages.git}"
packages_ref="${AUDIOWRT_PACKAGES_REF:-main}"
features="${FEATURES:-}"
jobs="${JOBS:-}"
verbosity="${VERBOSITY:-normal}"
builder_image="${BUILDER_IMAGE:-unknown}"

[[ "${AUDIOWRT_IN_CONTAINER:-0}" == "1" ]] || {
    echo "ERROR: scripts/build.sh is an internal container entry point." >&2
    echo "Run 'make build PLATFORM=<profile>' so AudioWRT uses the published openwrt-builder Docker image." >&2
    exit 2
}

[[ -n "$platform" ]] || { echo "ERROR: PLATFORM is required." >&2; exit 2; }
[[ -n "$jobs" ]] || jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: JOBS must be a positive integer." >&2; exit 2; }

case "$verbosity" in
    normal) make_verbosity=() ;;
    verbose) make_verbosity=(V=s) ;;
    debug) make_verbosity=(V=sc) ;;
    *) echo "ERROR: VERBOSITY must be normal, verbose or debug." >&2; exit 2 ;;
esac

make_run() {
    local cwd="$1"; shift
    echo "+ (cd $cwd && make $*)"
    make -C "$cwd" "$@" "${make_verbosity[@]}"
}

read_package_file() {
    grep -Ev '^[[:space:]]*(#|$)' "$1" || true
}

json_field() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]])' "$1" "$2"
}

download_file() {
    local url="$1" destination="$2"
    mkdir -p "$(dirname "$destination")"
    echo "Downloading: $url"
    python3 - "$url" "$destination" <<'PY'
import shutil
import sys
import urllib.request
url, destination = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url) as response, open(destination, "wb") as handle:
    shutil.copyfileobj(response, handle)
PY
}

extract_archive() {
    local url="$1" destination="$2" label="$3"
    rm -rf "$destination"
    mkdir -p "$destination"
    local archive="$destination/archive.tar.zst"
    download_file "$url" "$archive" >&2
    mkdir -p "$destination/extract"
    tar --zstd -xf "$archive" -C "$destination/extract"
    mapfile -t roots < <(find "$destination/extract" -mindepth 1 -maxdepth 1 -type d -print)
    if [[ "${#roots[@]}" -ne 1 ]]; then
        echo "ERROR: could not determine extracted $label directory." >&2
        exit 4
    fi
    printf '%s\n' "${roots[0]}"
}

resolved_release="$(OPENWRT_REPOSITORY="$openwrt_repo" bash "$repo_root/scripts/resolve-openwrt-ref.sh" "$requested_release")"
release="${resolved_release#v}"
safe_release="${release//./_}"
work_dir="$repo_root/.work/${platform}-${safe_release}"
source_dir="$work_dir/openwrt-source"
platform_metadata="$work_dir/platform.json"
selected_features="$work_dir/features.json"
artifacts_metadata="$work_dir/artifacts.json"
local_apks_dir="$work_dir/local-apks"
output_dir="$repo_root/output/$platform/$resolved_release"

printf 'AudioWRT build\n'
printf '  Platform: %s\n' "$platform"
printf '  OpenWrt release: %s -> %s\n' "$requested_release" "$resolved_release"
printf '  AudioWRT packages: %s\n' "$packages_ref"
printf '  Features: %s\n' "${features:-none}"
printf '  Builder image: %s\n' "$builder_image"
printf '  Jobs: %s\n' "$jobs"
printf '  Verbosity: %s\n' "$verbosity"

rm -rf "$work_dir" "$output_dir"
mkdir -p "$work_dir" "$output_dir"

# A clean checkout of the exact OpenWrt release is used only as authoritative
# device metadata. AudioWRT never builds from the moving openwrt-X.Y branch.
echo "Cloning exact OpenWrt release $resolved_release..."
git clone --filter=blob:none --no-checkout "$openwrt_repo" "$source_dir"
git -C "$source_dir" fetch --depth=1 origin "refs/tags/$resolved_release"
git -C "$source_dir" checkout --detach FETCH_HEAD
openwrt_commit="$(git -C "$source_dir" rev-parse HEAD)"

make_run "$source_dir" -s prepare-tmpinfo
python3 "$repo_root/scripts/resolve-platform.py" "$source_dir/tmp/.targetinfo" "$platform" > "$platform_metadata"
python3 "$repo_root/scripts/check-usb.py" "$platform_metadata" "$repo_root/config/usb-host-packages"
python3 "$repo_root/scripts/resolve-features.py" "$repo_root/config/features.map" "$features" > "$selected_features"

target="$(json_field "$platform_metadata" target)"
subtarget="$(json_field "$platform_metadata" subtarget)"

python3 "$repo_root/scripts/resolve-openwrt-artifacts.py" "$resolved_release" "$target" "$subtarget" > "$artifacts_metadata"
sdk_url="$(json_field "$artifacts_metadata" sdk_url)"
imagebuilder_url="$(json_field "$artifacts_metadata" imagebuilder_url)"
feeds_buildinfo_url="$(json_field "$artifacts_metadata" feeds_buildinfo_url)"

printf '  Target: %s/%s\n' "$target" "$subtarget"
printf '  SDK: %s\n' "$sdk_url"
printf '  ImageBuilder: %s\n' "$imagebuilder_url"

# Compile only AudioWRT-owned packages with the official SDK for the exact
# release. Unchanged OpenWrt packages remain binary dependencies from the
# official release repositories.
sdk_dir="$(extract_archive "$sdk_url" "$work_dir/sdk" "SDK")"
mkdir -p "$sdk_dir/package/audiowrt"
rsync -a "$repo_root/package/" "$sdk_dir/package/audiowrt/"

download_file "$feeds_buildinfo_url" "$sdk_dir/feeds.conf"
if [[ "$packages_ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
    feed_source="${packages_repo}^${packages_ref}"
else
    feed_source="${packages_repo};${packages_ref}"
fi
printf '\n# AudioWRT reusable packages\nsrc-git audiowrt %s\n' "$feed_source" >> "$sdk_dir/feeds.conf"

(
    cd "$sdk_dir"
    ./scripts/feeds update -a
    ./scripts/feeds install -a
)

audiowrt_packages_commit="$(git -C "$sdk_dir/feeds/audiowrt" rev-parse HEAD)"

mapfile -t firmware_packages < <(
    read_package_file "$repo_root/config/packages.add"
    python3 - "$selected_features" <<'PY'
import json, sys
for package in json.load(open(sys.argv[1], encoding="utf-8"))["packages"]:
    print(package)
PY
)

# Select only AudioWRT-owned roots in the SDK. make defconfig resolves their
# official and AudioWRT-owned dependencies. The SDK's existing target config is
# preserved.
for package in "${firmware_packages[@]}"; do
    if awk -F '|' -v package="$package" '$0 !~ /^[[:space:]]*#/ && $1 == package { found=1 } END { exit found ? 0 : 1 }' "$repo_root/config/package-build-targets"; then
        sed -i -E "/^(# )?CONFIG_PACKAGE_${package}(=| is not set)/d" "$sdk_dir/.config" 2>/dev/null || true
        printf 'CONFIG_PACKAGE_%s=m\n' "$package" >> "$sdk_dir/.config"
    fi
done

make_run "$sdk_dir" defconfig

mapfile -t build_targets < <(
    while IFS='|' read -r package target_path; do
        [[ -n "$package" && "$package" != \#* ]] || continue
        if grep -Eq "^CONFIG_PACKAGE_${package}=(y|m)$" "$sdk_dir/.config"; then
            printf '%s\n' "$target_path"
        fi
    done < "$repo_root/config/package-build-targets"
)

[[ "${#build_targets[@]}" -gt 0 ]] || {
    echo "ERROR: no AudioWRT SDK build targets were selected." >&2
    exit 5
}

make_run "$sdk_dir" package/download -j"$jobs"
for target_path in "${build_targets[@]}"; do
    make_run "$sdk_dir" "$target_path" -j"$jobs"
done

rm -rf "$local_apks_dir"
mkdir -p "$local_apks_dir"

# All APKs produced by the reusable AudioWRT feed are ours. Copy them all so
# custom dependencies such as librespot and bluez-alsa are available to the
# ImageBuilder when their wrapper feature is selected.
while IFS= read -r -d '' apk; do
    cp -f "$apk" "$local_apks_dir/"
done < <(find "$sdk_dir/bin/packages" -type f -path '*/audiowrt/*.apk' -print0 2>/dev/null || true)

# Distribution-only packages are local source packages rather than feed
# packages, so copy their APKs explicitly by package name.
for package in audiowrt-core audiowrt-provisioning audiowrt-storage luci-app-audiowrt-core; do
    while IFS= read -r -d '' apk; do
        cp -f "$apk" "$local_apks_dir/"
    done < <(find "$sdk_dir/bin/packages" -type f -name "${package}-*.apk" -print0 2>/dev/null || true)
done

local_apk_count="$(find "$local_apks_dir" -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d ' ')"
[[ "$local_apk_count" -gt 0 ]] || {
    echo "ERROR: SDK build did not produce AudioWRT APKs." >&2
    exit 6
}

# Assemble the final firmware from the official ImageBuilder for the same exact
# release. This deliberately avoids generating a custom ImageBuilder, so SDK
# host tools are never bundled into another ImageBuilder layer.
imagebuilder_dir="$(extract_archive "$imagebuilder_url" "$work_dir/imagebuilder" "ImageBuilder")"
mkdir -p "$imagebuilder_dir/packages"
cp -f "$local_apks_dir"/*.apk "$imagebuilder_dir/packages/"

package_args=()
while IFS= read -r package; do package_args+=("$package"); done < <(read_package_file "$repo_root/config/packages.add")
while IFS= read -r package; do package_args+=("$package"); done < <(python3 - "$selected_features" <<'PY'
import json, sys
for package in json.load(open(sys.argv[1], encoding="utf-8"))["packages"]:
    print(package)
PY
)
while IFS= read -r package; do package_args+=("-$package"); done < <(read_package_file "$repo_root/config/packages.remove")
package_string="${package_args[*]}"

make_run "$imagebuilder_dir" image \
    "PROFILE=$platform" \
    "PACKAGES=$package_string" \
    "FILES=$repo_root/files" \
    "BIN_DIR=$output_dir"

cp "$platform_metadata" "$output_dir/platform.json"
cp "$selected_features" "$output_dir/selected-features.json"
cp "$artifacts_metadata" "$output_dir/openwrt-artifacts.json"
cp "$sdk_dir/feeds.conf" "$output_dir/feeds.buildinfo"
cp "$repo_root/config/packages.add" "$output_dir/audiowrt-packages.add"
cp "$repo_root/config/packages.remove" "$output_dir/audiowrt-packages.remove"
cp "$repo_root/config/package-build-targets" "$output_dir/package-build-targets"
mkdir -p "$output_dir/local-apks"
cp -f "$local_apks_dir"/*.apk "$output_dir/local-apks/"
[[ -f "$sdk_dir/.config" ]] && cp "$sdk_dir/.config" "$output_dir/sdk.config"
[[ -f "$imagebuilder_dir/.config" ]] && cp "$imagebuilder_dir/.config" "$output_dir/imagebuilder.config"

python3 "$repo_root/scripts/image-size-report.py" \
    "$output_dir" \
    "$output_dir/image-size-report.json" \
    "$output_dir/image-size-report.txt"

audiowrt_commit="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf unknown)"

cat > "$output_dir/BUILD_INFO" <<EOF
BUILD_MODE=exact-release-sdk-imagebuilder
BUILDER_IMAGE=$builder_image
PLATFORM=$platform
TARGET=$target
SUBTARGET=$subtarget
OPENWRT_RELEASE=$resolved_release
OPENWRT_COMMIT=$openwrt_commit
SDK_URL=$sdk_url
IMAGEBUILDER_URL=$imagebuilder_url
OFFICIAL_FEEDS_BUILDINFO=$feeds_buildinfo_url
AUDIOWRT_COMMIT=$audiowrt_commit
AUDIOWRT_PACKAGES_REPOSITORY=$packages_repo
AUDIOWRT_PACKAGES_REF=$packages_ref
AUDIOWRT_PACKAGES_COMMIT=$audiowrt_packages_commit
FEATURES=${features:-none}
LOCAL_APKS=$local_apk_count
VERBOSITY=$verbosity
EOF

python3 - "$platform_metadata" "$selected_features" "$artifacts_metadata" "$output_dir/manifest.json" <<PY
import json, sys
platform_data = json.load(open(sys.argv[1], encoding="utf-8"))
features_data = json.load(open(sys.argv[2], encoding="utf-8"))
artifacts = json.load(open(sys.argv[3], encoding="utf-8"))
manifest = {
    "build_mode": "exact-release-sdk-imagebuilder",
    "builder_image": "$builder_image",
    "audiowrt_commit": "$audiowrt_commit",
    "audiowrt_packages_repository": "$packages_repo",
    "audiowrt_packages_ref": "$packages_ref",
    "audiowrt_packages_commit": "$audiowrt_packages_commit",
    "openwrt_repository": "$openwrt_repo",
    "openwrt_release": "$resolved_release",
    "openwrt_commit": "$openwrt_commit",
    "openwrt_artifacts": artifacts,
    "features": features_data["features"],
    "platform": platform_data,
    "local_apk_count": int("$local_apk_count"),
}
with open(sys.argv[4], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

printf '\nAudioWRT build complete.\nArtifacts: %s\n' "$output_dir"
cat "$output_dir/image-size-report.txt"
