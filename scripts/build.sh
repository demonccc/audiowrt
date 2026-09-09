#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="${PLATFORM:-}"
requested_release="${OPENWRT_RELEASE:-25.12.5}"
openwrt_repo="${OPENWRT_REPOSITORY:-https://github.com/openwrt/openwrt.git}"
packages_repo="${AUDIOWRT_PACKAGES_REPOSITORY:-https://github.com/demonccc/audiowrt-packages.git}"
packages_ref="${AUDIOWRT_PACKAGES_REF:-main}"
features="${FEATURES:-}"
jobs="${JOBS:-}"
verbosity="${VERBOSITY:-normal}"
builder_image="demonccc/openwrt-builder:latest"
cache_dir="${CACHE_DIR:-}"

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

if [[ -n "$cache_dir" ]]; then
    mkdir -p "$cache_dir"
    cache_dir="$(cd "$cache_dir" && pwd -P)"
    case "$cache_dir" in
        "$repo_root/.work"|"$repo_root/.work"/*|"$repo_root/output"|"$repo_root/output"/*)
            echo "ERROR: CACHE_DIR must be outside .work/ and output/." >&2
            exit 2
            ;;
    esac
    mkdir -p "$cache_dir/archives" "$cache_dir/dl"
fi

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

cache_archive_path() {
    local url="$1"
    [[ -n "$cache_dir" ]] || return 1
    local filename digest
    filename="$(basename "${url%%\?*}")"
    [[ -n "$filename" ]] || filename='download.tar.zst'
    digest="$(printf '%s' "$url" | sha256sum | awk '{print substr($1,1,20)}')"
    printf '%s\n' "$cache_dir/archives/$digest/$filename"
}

prepare_archive() {
    local url="$1" destination="$2" label="$3"
    local archive temporary

    if [[ -n "$cache_dir" ]]; then
        archive="$(cache_archive_path "$url")"
        if [[ -s "$archive" ]]; then
            echo "Cache hit for $label: $archive" >&2
            printf '%s\n' "$archive"
            return 0
        fi
        mkdir -p "$(dirname "$archive")"
        temporary="${archive}.part"
    else
        archive="$destination/archive.tar.zst"
        temporary="${archive}.part"
    fi

    rm -f "$temporary"
    download_file "$url" "$temporary" >&2
    mv -f "$temporary" "$archive"
    [[ -n "$cache_dir" ]] && echo "Cached $label: $archive" >&2
    printf '%s\n' "$archive"
}

extract_archive() {
    local url="$1" destination="$2" label="$3"
    rm -rf "$destination"
    mkdir -p "$destination"
    local archive
    archive="$(prepare_archive "$url" "$destination" "$label")"
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
build_plan="$work_dir/package-build-plan.txt"
registered_sources="$work_dir/sdk-audiowrt-sources.txt"
source_dependencies_file="$work_dir/source-build-dependencies.txt"
official_feeds_buildinfo="$work_dir/official-feeds.buildinfo"
output_dir="$repo_root/output/$platform/$resolved_release"

printf 'AudioWRT build\n'
printf '  Platform: %s\n' "$platform"
printf '  OpenWrt release: %s -> %s\n' "$requested_release" "$resolved_release"
printf '  AudioWRT packages: %s\n' "$packages_ref"
printf '  Features: %s\n' "${features:-none}"
printf '  Builder image: %s (fixed)\n' "$builder_image"
printf '  Jobs: %s\n' "$jobs"
printf '  Verbosity: %s\n' "$verbosity"
printf '  Download cache: %s\n' "${cache_dir:-disabled}"

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

mapfile -t firmware_packages < <(
    read_package_file "$repo_root/config/packages.add"
    python3 - "$selected_features" <<'PY'
import json, sys
for package in json.load(open(sys.argv[1], encoding="utf-8"))["packages"]:
    print(package)
PY
)

target="$(json_field "$platform_metadata" target)"
subtarget="$(json_field "$platform_metadata" subtarget)"

python3 "$repo_root/scripts/resolve-openwrt-artifacts.py" "$resolved_release" "$target" "$subtarget" > "$artifacts_metadata"
sdk_url="$(json_field "$artifacts_metadata" sdk_url)"
imagebuilder_url="$(json_field "$artifacts_metadata" imagebuilder_url)"
feeds_buildinfo_url="$(json_field "$artifacts_metadata" feeds_buildinfo_url)"

printf '  Target: %s/%s\n' "$target" "$subtarget"
printf '  SDK: %s\n' "$sdk_url"
printf '  ImageBuilder: %s\n' "$imagebuilder_url"

# Compile AudioWRT-owned packages with the official SDK for the exact release.
# Package-only AudioWRT packages are built with NO_DEPS=1 so unchanged OpenWrt
# packages remain official release binaries instead of being rebuilt from feed
# sources merely because they are runtime dependencies.
sdk_dir="$(extract_archive "$sdk_url" "$work_dir/sdk" "SDK")"

if [[ -n "$cache_dir" ]]; then
    rm -rf "$sdk_dir/dl"
    ln -s "$cache_dir/dl" "$sdk_dir/dl"
    echo "OpenWrt source download cache: $cache_dir/dl"
fi

mkdir -p "$sdk_dir/package/audiowrt"
rsync -a "$repo_root/package/" "$sdk_dir/package/audiowrt/"

# Keep the SDK's official exact-release feed configuration intact. We only
# update the feeds whose source trees are needed by AudioWRT package Makefiles:
# packages (for shared build helpers such as rust-package.mk) and audiowrt.
# The base feed remains available in feeds.conf for provenance/lazy source
# dependency resolution, but it is not installed into the SDK package tree for
# package-only builds.
[[ -s "$sdk_dir/feeds.conf.default" ]] || {
    echo "ERROR: official OpenWrt SDK is missing feeds.conf.default." >&2
    exit 5
}
cp "$sdk_dir/feeds.conf.default" "$sdk_dir/feeds.conf"
if ! grep -Eq '^[[:space:]]*src-git([[:space:]]+--root=package)?[[:space:]]+base[[:space:]]' "$sdk_dir/feeds.conf"; then
    echo "ERROR: official OpenWrt SDK feed config does not expose the base source feed." >&2
    exit 5
fi
download_file "$feeds_buildinfo_url" "$official_feeds_buildinfo"

if [[ "$packages_ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
    feed_source="${packages_repo}^${packages_ref}"
else
    feed_source="${packages_repo};${packages_ref}"
fi
printf '\n# AudioWRT reusable packages\nsrc-git audiowrt %s\n' "$feed_source" >> "$sdk_dir/feeds.conf"

(
    cd "$sdk_dir"
    ./scripts/feeds update packages audiowrt
)
audiowrt_packages_commit="$(git -C "$sdk_dir/feeds/audiowrt" rev-parse HEAD)"

# Register only AudioWRT feed source directories. Do not call scripts/feeds
# install for package-only AudioWRT packages because that recursively installs
# runtime dependencies (hostapd, dnsmasq, uhttpd, kernel libraries, etc.) as
# source packages and causes the SDK to rebuild them.
mkdir -p "$sdk_dir/package/feeds/audiowrt"
: > "$registered_sources"
while IFS='|' read -r package target_path extra; do
    [[ -n "$package" && "$package" != \#* ]] || continue
    [[ -z "${extra:-}" ]] || {
        echo "ERROR: invalid package-build-targets entry for $package." >&2
        exit 5
    }
    [[ "$target_path" == package/feeds/audiowrt/*/compile ]] || continue

    source_rel="${target_path#package/feeds/audiowrt/}"
    source_rel="${source_rel%/compile}"
    source_path="$sdk_dir/feeds/audiowrt/$source_rel"
    destination="$sdk_dir/package/feeds/audiowrt/$source_rel"

    [[ -d "$source_path" ]] || {
        echo "ERROR: AudioWRT feed source directory does not exist: $source_path" >&2
        exit 5
    }

    mkdir -p "$(dirname "$destination")"
    if [[ ! -e "$destination" && ! -L "$destination" ]]; then
        ln -s "$source_path" "$destination"
    fi
    printf '%s|%s\n' "$package" "$source_rel" >> "$registered_sources"
done < "$repo_root/config/package-build-targets"

# Select only the AudioWRT-owned firmware roots requested by packages.add plus
# FEATURES. The SDK's shipped package selections are deliberately not used as
# AudioWRT build intent.
for package in "${firmware_packages[@]}"; do
    if awk -F '|' -v package="$package" '$0 !~ /^[[:space:]]*#/ && $1 == package { found=1 } END { exit found ? 0 : 1 }' "$repo_root/config/package-build-targets"; then
        sed -i -E "/^(# )?CONFIG_PACKAGE_${package}(=| is not set)/d" "$sdk_dir/.config" 2>/dev/null || true
        printf 'CONFIG_PACKAGE_%s=m\n' "$package" >> "$sdk_dir/.config"
    fi
done

make_run "$sdk_dir" defconfig

packageinfo="$sdk_dir/tmp/.packageinfo"
[[ -s "$packageinfo" ]] || {
    echo "ERROR: OpenWrt SDK package metadata was not generated: $packageinfo" >&2
    exit 5
}

# Resolve only the AudioWRT-owned dependency closure of the explicitly
# requested firmware roots. Optional AudioWRT source packages such as librespot
# and bluez-alsa are included only when their feature wrapper requires them.
python3 "$repo_root/scripts/resolve-package-build-targets.py" \
    "$repo_root/config/package-build-targets" \
    "$packageinfo" \
    "${firmware_packages[@]}" > "$build_plan"

mapfile -t build_specs < "$build_plan"
[[ "${#build_specs[@]}" -gt 0 ]] || {
    echo "ERROR: no AudioWRT SDK build targets were selected." >&2
    exit 5
}

declare -A source_build_package=()
while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    source_build_package["$package"]=1
done < <(read_package_file "$repo_root/config/source-build-packages")

build_packages=()
package_only_packages=()
package_only_targets=()
source_packages=()
source_targets=()

for spec in "${build_specs[@]}"; do
    package="${spec%%|*}"
    target_path="${spec#*|}"
    [[ -n "$package" && -n "$target_path" && "$target_path" != "$spec" ]] || {
        echo "ERROR: invalid AudioWRT package build plan entry: $spec" >&2
        exit 5
    }

    build_packages+=("$package")
    if [[ -n "${source_build_package[$package]+x}" ]]; then
        source_packages+=("$package")
        source_targets+=("$target_path")
    else
        package_only_packages+=("$package")
        package_only_targets+=("$target_path")
    fi
done

printf '  AudioWRT SDK build packages:\n'
printf '    %s\n' "${build_packages[@]}"
printf '  Package-only AudioWRT packages (NO_DEPS=1):\n'
printf '    %s\n' "${package_only_packages[@]}"
if [[ "${#source_packages[@]}" -gt 0 ]]; then
    printf '  AudioWRT source packages:\n'
    printf '    %s\n' "${source_packages[@]}"
fi

# Package-only AudioWRT packages need no OpenWrt source dependency compilation.
# For the small set of AudioWRT-owned packages that compile upstream code, the
# SDK must stage their actual build/link dependencies. Resolve those explicitly
# and install source definitions only for that source-build path.
: > "$source_dependencies_file"
source_dependencies=()
if [[ "${#source_packages[@]}" -gt 0 ]]; then
    python3 "$repo_root/scripts/resolve-source-build-dependencies.py" \
        "$repo_root/config/package-build-targets" \
        "$packageinfo" \
        "${source_packages[@]}" > "$source_dependencies_file"
    mapfile -t source_dependencies < "$source_dependencies_file"

    if [[ "${#source_dependencies[@]}" -gt 0 ]]; then
        (
            cd "$sdk_dir"
            ./scripts/feeds update base
            printf 'Installing source-build dependencies for AudioWRT source packages:\n'
            printf '  %s\n' "${source_dependencies[@]}"
            ./scripts/feeds install "${source_dependencies[@]}"
        )
        make_run "$sdk_dir" defconfig
    fi
fi

# Download and compile package-only roots without traversing runtime dependency
# prerequisites. This is the critical boundary that keeps hostapd, dnsmasq,
# uhttpd, kernel packages, libraries, etc. as official release binaries.
package_only_download_targets=()
for target_path in "${package_only_targets[@]}"; do
    package_only_download_targets+=("${target_path%/compile}/download")
done
if [[ "${#package_only_download_targets[@]}" -gt 0 ]]; then
    make_run "$sdk_dir" "${package_only_download_targets[@]}" NO_DEPS=1 -j"$jobs"
fi

# AudioWRT source packages are the only targets allowed to traverse build
# dependencies, because they genuinely compile/link upstream code.
source_download_targets=()
for target_path in "${source_targets[@]}"; do
    source_download_targets+=("${target_path%/compile}/download")
done
if [[ "${#source_download_targets[@]}" -gt 0 ]]; then
    make_run "$sdk_dir" "${source_download_targets[@]}" -j"$jobs"
    make_run "$sdk_dir" "${source_targets[@]}" -j"$jobs"
fi

if [[ "${#package_only_targets[@]}" -gt 0 ]]; then
    make_run "$sdk_dir" "${package_only_targets[@]}" NO_DEPS=1 -j"$jobs"
fi

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
# release. OpenWrt runtime dependencies are resolved from the official release
# repositories; only locally built AudioWRT APKs are injected.
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
cp "$sdk_dir/feeds.conf" "$output_dir/sdk-feeds.conf"
cp "$official_feeds_buildinfo" "$output_dir/official-feeds.buildinfo"
cp "$registered_sources" "$output_dir/sdk-audiowrt-sources.txt"
cp "$source_dependencies_file" "$output_dir/source-build-dependencies.txt"
cp "$repo_root/config/packages.add" "$output_dir/audiowrt-packages.add"
cp "$repo_root/config/packages.remove" "$output_dir/audiowrt-packages.remove"
cp "$repo_root/config/package-build-targets" "$output_dir/package-build-targets"
cp "$repo_root/config/source-build-packages" "$output_dir/source-build-packages"
cp "$build_plan" "$output_dir/package-build-plan.txt"
mkdir -p "$output_dir/local-apks"
cp -f "$local_apks_dir"/*.apk "$output_dir/local-apks/"
[[ -f "$sdk_dir/.config" ]] && cp "$sdk_dir/.config" "$output_dir/sdk.config"
[[ -f "$imagebuilder_dir/.config" ]] && cp "$imagebuilder_dir/.config" "$output_dir/imagebuilder.config"

python3 "$repo_root/scripts/image-size-report.py" \
    "$output_dir" \
    "$output_dir/image-size-report.json" \
    "$output_dir/image-size-report.txt"

audiowrt_commit="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf unknown)"
cache_enabled='no'
[[ -n "$cache_dir" ]] && cache_enabled='yes'

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
SDK_FEEDS_CONFIG=official-sdk-default+audiowrt
SDK_PACKAGE_ONLY_MODE=NO_DEPS
AUDIOWRT_COMMIT=$audiowrt_commit
AUDIOWRT_PACKAGES_REPOSITORY=$packages_repo
AUDIOWRT_PACKAGES_REF=$packages_ref
AUDIOWRT_PACKAGES_COMMIT=$audiowrt_packages_commit
FEATURES=${features:-none}
AUDIOWRT_BUILD_PACKAGES=${build_packages[*]}
AUDIOWRT_PACKAGE_ONLY_PACKAGES=${package_only_packages[*]}
AUDIOWRT_SOURCE_PACKAGES=${source_packages[*]}
SOURCE_BUILD_DEPENDENCIES=${source_dependencies[*]}
LOCAL_APKS=$local_apk_count
VERBOSITY=$verbosity
CACHE_ENABLED=$cache_enabled
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
    "sdk_feeds_config": "official-sdk-default+audiowrt",
    "sdk_package_only_mode": "NO_DEPS",
    "features": features_data["features"],
    "platform": platform_data,
    "audiowrt_build_packages": "${build_packages[*]}".split(),
    "audiowrt_package_only_packages": "${package_only_packages[*]}".split(),
    "audiowrt_source_packages": "${source_packages[*]}".split(),
    "source_build_dependencies": "${source_dependencies[*]}".split(),
    "local_apk_count": int("$local_apk_count"),
    "cache_enabled": "$cache_enabled" == "yes",
}
with open(sys.argv[4], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

printf '\nAudioWRT build complete.\nArtifacts: %s\n' "$output_dir"
cat "$output_dir/image-size-report.txt"
