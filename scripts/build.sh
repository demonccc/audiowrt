#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version_file="$repo_root/VERSION"
[[ -f "$version_file" ]] || { echo "ERROR: AudioWRT VERSION file is missing." >&2; exit 2; }
audiowrt_version="$(tr -d '[:space:]' < "$version_file")"
[[ "$audiowrt_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "ERROR: AudioWRT VERSION must use semantic versioning (MAJOR.MINOR.PATCH)." >&2
    exit 2
}
audiowrt_profile="${AUDIOWRT_PROFILE:-tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5}"
openwrt_repo="${OPENWRT_REPOSITORY:-https://github.com/openwrt/openwrt.git}"
packages_repo="${AUDIOWRT_PACKAGES_REPOSITORY:-https://github.com/demonccc/audiowrt-packages.git}"
packages_ref="${AUDIOWRT_PACKAGES_REF:-main}"
jobs="${JOBS:-}"
verbosity="${VERBOSITY:-normal}"
builder_image="demonccc/openwrt-builder:latest"
cache_dir="${CACHE_DIR:-}"
build_mode="${AUDIOWRT_BUILD_MODE:-firmware}"
package_request="${AUDIOWRT_PACKAGE:-all}"

[[ "${AUDIOWRT_IN_CONTAINER:-0}" == "1" ]] || {
    echo "ERROR: scripts/build.sh is an internal container entry point." >&2
    echo "Run 'make build ...' or 'make packages ...' so AudioWRT uses the published openwrt-builder Docker image." >&2
    exit 2
}

case "$build_mode" in
    firmware|packages) ;;
    *) echo "ERROR: AUDIOWRT_BUILD_MODE must be firmware or packages." >&2; exit 2 ;;
esac
package_requests=()
if [[ "$build_mode" == "packages" ]]; then
    read -r -a package_requests <<< "$package_request"
    if [[ "${#package_requests[@]}" -eq 0 ]]; then
        echo "ERROR: AUDIOWRT_PACKAGE must be all or one or more space-separated AudioWRT package names." >&2
        exit 2
    fi
    if [[ " ${package_requests[*]} " == *" all "* && "${#package_requests[@]}" -ne 1 ]]; then
        echo "ERROR: 'all' cannot be combined with explicit package names." >&2
        exit 2
    fi
fi

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
    local status

    echo "+ (cd $cwd && make $*)"
    if make -C "$cwd" "$@" "${make_verbosity[@]}"; then
        return 0
    else
        status=$?
    fi

    if [[ "$verbosity" == "normal" ]]; then
        local -a retry_args=()
        local skip_jobs_value=0
        local arg

        for arg in "$@"; do
            if (( skip_jobs_value )); then
                skip_jobs_value=0
                continue
            fi
            case "$arg" in
                -j|--jobs)
                    skip_jobs_value=1
                    ;;
                -j[0-9]*|--jobs=*)
                    ;;
                *)
                    retry_args+=("$arg")
                    ;;
            esac
        done

        echo >&2
        echo "AudioWRT: make failed; repeating with -j1 V=s for diagnostics." >&2
        make -C "$cwd" "${retry_args[@]}" -j1 V=s || true
    fi

    return "$status"
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

if [[ "$build_mode" == "packages" ]]; then
    work_dir="$repo_root/.work/packages/$audiowrt_profile"
    output_dir="$repo_root/output/packages/$audiowrt_profile"
else
    work_dir="$repo_root/.work/$audiowrt_profile"
    output_dir="$repo_root/output/$audiowrt_profile"
fi
source_dir="$work_dir/openwrt-source"
resolved_profile="$work_dir/audiowrt-profile.json"
packages_add_file="$work_dir/resolved-packages.add"
packages_remove_file="$work_dir/resolved-packages.remove"
platform_metadata="$work_dir/platform.json"
artifacts_metadata="$work_dir/artifacts.json"
local_apks_dir="$work_dir/local-apks"
build_plan="$work_dir/package-build-plan.txt"
registered_sources="$work_dir/sdk-audiowrt-sources.txt"
source_dependencies_file="$work_dir/source-build-dependencies.txt"
official_feeds_buildinfo="$work_dir/official-feeds.buildinfo"
official_version_buildinfo="$work_dir/official-version.buildinfo"

rm -rf "$work_dir" "$output_dir"
mkdir -p "$work_dir" "$output_dir"

python3 "$repo_root/scripts/resolve-audiowrt-profile.py" \
    "$repo_root/profiles" "$repo_root/config/package-groups" "$audiowrt_profile" > "$resolved_profile"

platform="$(json_field "$resolved_profile" openwrt_profile)"
profile_package_groups="$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1], encoding="utf-8"))["package_groups"]))' "$resolved_profile")"
openwrt_source="$(json_field "$resolved_profile" openwrt_source)"
openwrt_version="$(json_field "$resolved_profile" openwrt_version)"
expected_target="$(json_field "$resolved_profile" target)"
expected_subtarget="$(json_field "$resolved_profile" subtarget)"
squashfs_block_size="$(json_field "$resolved_profile" squashfs_block_size)"
case "$openwrt_source" in
    release)
        resolved_release="$(bash "$repo_root/scripts/resolve-openwrt-ref.sh" "$openwrt_version")"
        release="${resolved_release#v}"
        ;;
    snapshot)
        resolved_release="snapshot"
        release="snapshot"
        ;;
    *)
        echo "ERROR: unsupported OpenWrt source in resolved profile: $openwrt_source" >&2
        exit 2
        ;;
esac
python3 - "$resolved_profile" "$packages_add_file" "$packages_remove_file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for key, destination in (("packages_add", sys.argv[2]), ("packages_remove", sys.argv[3])):
    with open(destination, "w", encoding="utf-8") as handle:
        handle.write("\n".join(data[key]) + "\n")
PY

printf 'AudioWRT build\n'
printf '  Build mode: %s\n' "$build_mode"
printf '  Profile: %s\n' "$audiowrt_profile"
printf '  Package groups: %s\n' "$profile_package_groups"
printf '  OpenWrt profile: %s (%s/%s)\n' "$platform" "$expected_target" "$expected_subtarget"
printf '  OpenWrt source: %s %s\n' "$openwrt_source" "$openwrt_version"
printf '  AudioWRT packages: %s\n' "$packages_ref"
printf '  Builder image: %s (fixed)\n' "$builder_image"
printf '  Jobs: %s\n' "$jobs"
printf '  Verbosity: %s\n' "$verbosity"
printf '  Download cache: %s\n' "${cache_dir:-disabled}"
if [[ "$build_mode" == "packages" ]]; then
    printf '  Package selection: %s\n' "$package_request"
fi

# A release profile uses its exact tag. A snapshot profile deliberately uses
# the moving main branch and is recorded as such in the build provenance.
if [[ "$openwrt_source" == "release" ]]; then
    echo "Cloning exact OpenWrt release $resolved_release..."
    git clone --filter=blob:none --no-checkout "$openwrt_repo" "$source_dir"
    git -C "$source_dir" fetch --depth=1 origin "refs/tags/$resolved_release"
    git -C "$source_dir" checkout --detach FETCH_HEAD
else
    echo "Cloning current OpenWrt main for snapshot metadata..."
    git clone --filter=blob:none --depth=1 --branch main "$openwrt_repo" "$source_dir"
fi
openwrt_commit="$(git -C "$source_dir" rev-parse HEAD)"

if [[ "${AUDIOWRT_SKIP_HOST_PREREQ:-0}" == "1" ]]; then
    mkdir -p "$source_dir/staging_dir/host"
    touch "$source_dir/staging_dir/host/.prereq-build"
fi

make_run "$source_dir" -s prepare-tmpinfo
python3 "$repo_root/scripts/resolve-platform.py" "$source_dir/tmp/.targetinfo" "$platform" > "$platform_metadata"

mapfile -t profile_firmware_packages < <(read_package_file "$packages_add_file")
firmware_packages=("${profile_firmware_packages[@]}")
if [[ "$build_mode" == "packages" && "$package_request" != "all" ]]; then
    firmware_packages=()
    declare -A requested_package_seen=()
    for package in "${package_requests[@]}"; do
        if ! awk -F '|' -v package="$package" '$0 !~ /^[[:space:]]*#/ && $1 == package { found=1 } END { exit found ? 0 : 1 }' \
            "$repo_root/config/build/package-build-targets"; then
            echo "ERROR: unknown AudioWRT package: $package" >&2
            exit 2
        fi
        if [[ -z "${requested_package_seen[$package]+x}" ]]; then
            firmware_packages+=("$package")
            requested_package_seen["$package"]=1
        fi
    done
fi

target="$(json_field "$platform_metadata" target)"
subtarget="$(json_field "$platform_metadata" subtarget)"
arch_packages="$(json_field "$platform_metadata" arch_packages)"
if [[ "$target" != "$expected_target" || "$subtarget" != "$expected_subtarget" ]]; then
    echo "ERROR: profile $audiowrt_profile declares $expected_target/$expected_subtarget," >&2
    echo "but OpenWrt resolves $platform to $target/$subtarget." >&2
    exit 5
fi

python3 "$repo_root/scripts/resolve-openwrt-artifacts.py" "$release" "$target" "$subtarget" > "$artifacts_metadata"
sdk_url="$(json_field "$artifacts_metadata" sdk_url)"
imagebuilder_url="$(json_field "$artifacts_metadata" imagebuilder_url)"
feeds_buildinfo_url="$(json_field "$artifacts_metadata" feeds_buildinfo_url)"
version_buildinfo_url="$(json_field "$artifacts_metadata" version_buildinfo_url)"
openwrt_base_url="$(json_field "$artifacts_metadata" base_url)"
kmod_bluetooth_url="$(json_field "$artifacts_metadata" kmod_bluetooth_url)"
kmod_btmtk_url="$(json_field "$artifacts_metadata" kmod_btmtk_url)"
kmod_btusb_url="$(json_field "$artifacts_metadata" kmod_btusb_url)"
kmods_sha256sums_url="$(json_field "$artifacts_metadata" kmods_sha256sums_url)"

printf '  Target: %s/%s (%s)\n' "$target" "$subtarget" "$arch_packages"
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

# AudioWRT needs only the Bluetooth core plus USB HCI transports. Reuse the
# modules produced and signed for this exact OpenWrt kernel ABI, but repackage
# them without RFCOMM, BNEP or HIDP. This preserves binary compatibility and
# avoids compiling or patching the release kernel.
prepare_bluetooth_package() {
bluetooth_module_source="$sdk_dir/feeds/audiowrt/audiowrt-kmod-bluetooth"
[[ -d "$bluetooth_module_source" ]] || {
    echo "ERROR: AudioWRT minimal Bluetooth kernel package source is missing." >&2
    exit 5
}
bluetooth_stage="$work_dir/prebuilt-bluetooth-modules"
rm -rf "$bluetooth_stage"
mkdir -p "$bluetooth_stage/apks" "$bluetooth_stage/extracted" "$bluetooth_module_source/files"
download_file "$kmods_sha256sums_url" "$bluetooth_stage/sha256sums"

for module_url in "$kmod_bluetooth_url" "$kmod_btmtk_url" "$kmod_btusb_url"; do
    module_apk="$bluetooth_stage/apks/$(basename "$module_url")"
    download_file "$module_url" "$module_apk"
    module_path="${module_url#"$openwrt_base_url"}"
    [[ "$module_path" != "$module_url" && -n "$module_path" ]] || {
        echo "ERROR: kernel module URL is outside the OpenWrt target: $module_url" >&2
        exit 5
    }
    python3 "$repo_root/scripts/verify-openwrt-checksum.py" \
        "$bluetooth_stage/sha256sums" "$module_path" "$module_apk"
    "$sdk_dir/staging_dir/host/bin/apk" --allow-untrusted extract \
        --destination "$bluetooth_stage/extracted" "$module_apk"
done

for module in bluetooth.ko btmtk.ko btintel.ko btrtl.ko btusb.ko; do
    mapfile -t module_matches < <(find "$bluetooth_stage/extracted" -type f -name "$module" -print)
    [[ "${#module_matches[@]}" -eq 1 ]] || {
        echo "ERROR: expected one exact-release $module, found ${#module_matches[@]}." >&2
        exit 5
    }
    cp -f "${module_matches[0]}" "$bluetooth_module_source/files/$module"
done

for omitted in rfcomm.ko bnep.ko hidp.ko; do
    [[ ! -e "$bluetooth_module_source/files/$omitted" ]] || {
        echo "ERROR: omitted Bluetooth module leaked into AudioWRT package: $omitted" >&2
        exit 5
    }
done
}

register_official_sdk_source() {
    local feed="$1" source_rel="$2"
    local source_path="$sdk_dir/feeds/$feed/$source_rel"
    local destination="$sdk_dir/package/feeds/$feed/$(basename "$source_rel")"

    [[ -d "$source_path" ]] || {
        echo "ERROR: official OpenWrt source directory is missing: $source_path" >&2
        exit 5
    }
    mkdir -p "$(dirname "$destination")"
    if [[ ! -e "$destination" && ! -L "$destination" ]]; then
        ln -s "$source_path" "$destination"
    fi
}

prepared_source_dir() {
    local source_name="$1" allow_variants="${2:-0}"
    local -a matches=()
    mapfile -t matches < <(
        find "$sdk_dir/build_dir" -mindepth 2 -maxdepth 2 -type d \
            -name "$source_name-*" -print 2>/dev/null | sort
    )
    [[ "${#matches[@]}" -gt 0 ]] || {
        echo "ERROR: no prepared source tree found for $source_name." >&2
        exit 5
    }
    if [[ "$allow_variants" != "1" && "${#matches[@]}" -ne 1 ]]; then
        echo "ERROR: expected one prepared source tree for $source_name, found ${#matches[@]}." >&2
        exit 5
    fi
    # OpenWrt may prepare several build variants from the same source tree
    # (ustream-ssl: mbedTLS/OpenSSL/WolfSSL). Public source headers are common
    # to those variants, so callers that explicitly allow variants may use the
    # first deterministic prepared tree without compiling any variant.
    printf '%s\n' "${matches[0]}"
}

stage_official_link_stub() {
    local package="$1" feed="$2" library_glob="$3" linker_name="$4"
    local target_staging="$5"
    shift 5
    local provider_name="$package"
    if [[ "${1:-}" == "--provider-name" ]]; then
        [[ "$#" -ge 2 ]] || {
            echo "ERROR: --provider-name requires a logical package name for $package." >&2
            exit 5
        }
        provider_name="$2"
        shift 2
    fi
    local package_stage="$work_dir/prebuilt-sdk/$package"
    local package_url package_apk library soname readelf_bin target_cc stub_source runtime_pkg
    local -a libraries=()

    package_url="$(python3 "$repo_root/scripts/resolve-openwrt-package.py" \
        "$release" "$arch_packages" "$feed" "$package")"
    package_apk="$package_stage/$(basename "$package_url")"
    rm -rf "$package_stage"
    mkdir -p "$package_stage/extracted"
    download_file "$package_url" "$package_apk"
    "$sdk_dir/staging_dir/host/bin/apk" --allow-untrusted extract \
        --destination "$package_stage/extracted" "$package_apk"

    mapfile -t libraries < <(find "$package_stage/extracted" -type f -name "$library_glob" -print)
    [[ "${#libraries[@]}" -eq 1 ]] || {
        echo "ERROR: expected one $library_glob in official $package APK, found ${#libraries[@]}." >&2
        exit 5
    }
    library="${libraries[0]}"

    # Only select cross-tools from the target toolchain staging directory.
    # staging_dir/host/bin also contains helpers such as mklibs-readelf; those
    # are host utilities and do not have a matching target compiler.
    local -a target_readelf_candidates=()
    local -a target_cc_candidates=()
    local -A target_tool_pair_seen=()
    local candidate paired_cc canonical_readelf canonical_cc pair_key
    while IFS= read -r candidate; do
        paired_cc="${candidate%readelf}gcc"
        [[ -x "$paired_cc" ]] || continue

        # OpenWrt SDKs may expose multiple target-triplet aliases for the same
        # toolchain (for example mips-openwrt-linux-readelf and
        # mips-openwrt-linux-musl-readelf). Collapse aliases by their resolved
        # readelf/gcc pair instead of treating each pathname as a toolchain.
        canonical_readelf="$(readlink -f "$candidate" 2>/dev/null || true)"
        canonical_cc="$(readlink -f "$paired_cc" 2>/dev/null || true)"
        [[ -x "$canonical_readelf" && -x "$canonical_cc" ]] || continue

        pair_key="$canonical_readelf|$canonical_cc"
        [[ -z "${target_tool_pair_seen[$pair_key]+x}" ]] || continue
        target_tool_pair_seen["$pair_key"]=1
        target_readelf_candidates+=("$canonical_readelf")
        target_cc_candidates+=("$canonical_cc")
    done < <(
        find "$sdk_dir/staging_dir" -mindepth 3 -maxdepth 4 \( -type f -o -type l \) -print 2>/dev/null |
            grep '/toolchain-[^/]*/bin/[^/]*-readelf$' |
            sort -u
    )

    [[ "${#target_readelf_candidates[@]}" -eq 1 ]] || {
        echo "ERROR: expected exactly one distinct target readelf/gcc toolchain pair, found ${#target_readelf_candidates[@]}." >&2
        if [[ "${#target_readelf_candidates[@]}" -gt 0 ]]; then
            printf '  %s\n' "${target_readelf_candidates[@]}" >&2
        fi
        exit 5
    }

    readelf_bin="${target_readelf_candidates[0]}"
    target_cc="${target_cc_candidates[0]}"
    printf 'Official %s runtime library: %s\n' "$package" "$library"
    file "$library" || true
    if ! "$readelf_bin" -h "$library"; then
        echo "ERROR: official $package APK did not extract a valid target ELF library." >&2
        exit 5
    fi

    soname="$("$readelf_bin" -d "$library" 2>/dev/null | sed -n 's/.*SONAME.*\[\(.*\)\].*/\1/p' | head -n1)"
    [[ -n "$soname" ]] || soname="$(basename "$library")"

    # Runtime APK libraries are aggressively stripped by OpenWrt and have no
    # section headers. They are valid runtime ELFs, but GNU ld cannot consume
    # them as development libraries. Build a tiny target-architecture link stub
    # carrying the exact runtime SONAME. Callers may list the small set of
    # symbols they reference, or request every exported dynamic symbol when a
    # complex upstream package (such as wpa_supplicant) uses a wider API.
    mkdir -p "$target_staging/usr/lib" "$target_staging/pkginfo"
    if [[ "${1:-}" == "--all-dynamic-symbols" ]]; then
        python3 "$repo_root/scripts/create-elf-link-stub.py" \
            "$readelf_bin" "$target_cc" "$library" \
            "$target_staging/usr/lib/$linker_name" "$soname"
    else
        stub_source="$package_stage/link-stub.c"
        : > "$stub_source"
        for symbol in "$@"; do
            [[ "$symbol" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
                echo "ERROR: invalid link-stub symbol for $package: $symbol" >&2
                exit 5
            }

            # uloop exposes two pieces used by inline helpers in uloop.h rather
            # than through ordinary function calls. Keep their symbol kind
            # compatible with the real library.
            case "$symbol" in
                uloop_cancelled)
                    printf 'unsigned char uloop_cancelled;\n' >> "$stub_source"
                    ;;
                uloop_run_timeout)
                    printf 'int uloop_run_timeout(int timeout) { (void)timeout; return 0; }\n' >> "$stub_source"
                    ;;
                *)
                    printf 'void %s(void) {}\n' "$symbol" >> "$stub_source"
                    ;;
            esac
        done

        "$target_cc" -shared -fPIC -Wl,-soname,"$soname" \
            -o "$target_staging/usr/lib/$linker_name" "$stub_source"
    fi

    # Downstream AudioWRT libraries record the real runtime SONAME in DT_NEEDED.
    # Keep an SDK-only alias for that SONAME so GNU ld can resolve transitive
    # dependencies while linking codec players. The alias points to the stub,
    # never to the stripped runtime APK library.
    if [[ "$soname" != "$linker_name" ]]; then
        ln -sf "$linker_name" "$target_staging/usr/lib/$soname"
    fi

    # OpenWrt CheckDependencies expands the package's logical DEPENDS and then
    # concatenates <dependency>.provides. ABI-versioned runtime APKs use a
    # different concrete name (for example libmbedtls21), so keep metadata for
    # both the logical dependency and the concrete runtime package.
    runtime_pkg="$(basename "$package_apk" .apk)"
    runtime_pkg="${runtime_pkg%%-[0-9]*}"
    for provides_file in \
        "$target_staging/pkginfo/$provider_name.provides" \
        "$target_staging/pkginfo/$package.provides" \
        "$target_staging/pkginfo/$runtime_pkg.provides"; do
        touch "$provides_file"
        grep -Fxq "$soname" "$provides_file" || printf '%s\n' "$soname" >> "$provides_file"
    done
}

copy_single_header() {
    local root="$1" name="$2" destination="$3"
    local -a matches=()
    mapfile -t matches < <(find "$root" -type f -name "$name" -print 2>/dev/null | sort)
    [[ "${#matches[@]}" -eq 1 ]] || {
        echo "ERROR: expected one $name under $root, found ${#matches[@]}." >&2
        exit 5
    }
    cp -f "${matches[0]}" "$destination"
}

prepare_native_player_sdk() {
    local -a target_staging_matches=() ustream_headers=()
    local target_staging libubox_src uclient_src ustream_header

    mapfile -t target_staging_matches < <(
        find "$sdk_dir/staging_dir" -mindepth 1 -maxdepth 1 -type d -name 'target-*' -print
    )
    [[ "${#target_staging_matches[@]}" -eq 1 ]] || {
        echo "ERROR: expected one target staging directory, found ${#target_staging_matches[@]}." >&2
        exit 5
    }
    target_staging="${target_staging_matches[0]}"

    make_run "$sdk_dir" \
        package/feeds/base/libubox/prepare \
        package/feeds/base/uclient/prepare \
        package/feeds/base/ustream-ssl/prepare \
        NO_DEPS=1 -j"$jobs"

    libubox_src="$(prepared_source_dir libubox)"
    uclient_src="$(prepared_source_dir uclient)"
    mapfile -t ustream_headers < <(
        find "$sdk_dir/build_dir" -type f -name 'ustream-ssl.h' \
            -path '*/ustream-ssl-*/*' -print 2>/dev/null | sort
    )
    [[ "${#ustream_headers[@]}" -gt 0 ]] || {
        echo "ERROR: no prepared ustream-ssl public header found." >&2
        exit 5
    }
    ustream_header="${ustream_headers[0]}"

    mkdir -p "$target_staging/usr/include/libubox"
    find "$libubox_src" -maxdepth 1 -type f -name '*.h' -exec cp -f {} "$target_staging/usr/include/libubox/" \;
    find "$uclient_src" -maxdepth 1 -type f -name '*.h' -exec cp -f {} "$target_staging/usr/include/libubox/" \;
    cp -f "$ustream_header" "$target_staging/usr/include/libubox/ustream-ssl.h"

    [[ -f "$target_staging/usr/include/libubox/uloop.h" ]] || {
        echo "ERROR: libubox headers were not staged." >&2
        exit 5
    }
    [[ -f "$target_staging/usr/include/libubox/uclient.h" ]] || {
        echo "ERROR: uclient headers were not staged." >&2
        exit 5
    }
    [[ -f "$target_staging/usr/include/libubox/ustream-ssl.h" ]] || {
        echo "ERROR: ustream-ssl headers were not staged." >&2
        exit 5
    }

    stage_official_link_stub libubox base 'libubox.so.*' libubox.so "$target_staging" \
        uloop_cancelled uloop_init uloop_run_timeout uloop_done
    stage_official_link_stub libuclient base 'libuclient.so*' libuclient.so "$target_staging" \
        uclient_disconnect uclient_http_status_redirect uclient_http_redirect \
        uclient_read uclient_new uclient_set_timeout uclient_new_ssl_context \
        uclient_http_set_ssl_ctx uclient_connect uclient_http_set_request_type \
        uclient_http_reset_headers uclient_http_set_header uclient_request uclient_free

    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-flac "* ]]; then
        local flac_src
        make_run "$sdk_dir" package/feeds/packages/flac/prepare NO_DEPS=1 -j"$jobs"
        flac_src="$(prepared_source_dir flac)"
        mkdir -p "$target_staging/usr/include/FLAC"
        cp -f "$flac_src"/include/FLAC/*.h "$target_staging/usr/include/FLAC/"
        [[ -f "$target_staging/usr/include/FLAC/stream_decoder.h" ]] || {
            echo "ERROR: FLAC headers were not staged." >&2
            exit 5
        }
        stage_official_link_stub libflac packages 'libFLAC.so.*' libFLAC.so "$target_staging" \
            FLAC__stream_decoder_new FLAC__stream_decoder_init_FILE \
            FLAC__stream_decoder_process_until_end_of_stream \
            FLAC__stream_decoder_finish FLAC__stream_decoder_delete
    fi

    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-mp3 "* ]]; then
        local mad_src
        # libmad 0.16.4 generates mad.h from its CMake configuration. Prepare
        # alone leaves only the source inputs, while configure creates the public
        # header without compiling or replacing the official runtime library.
        make_run "$sdk_dir" package/feeds/packages/libmad/configure NO_DEPS=1 -j"$jobs"
        mad_src="$(prepared_source_dir libmad)"
        mkdir -p "$target_staging/usr/include"
        copy_single_header "$mad_src" mad.h "$target_staging/usr/include/mad.h"
        stage_official_link_stub libmad packages 'libmad.so.*' libmad.so "$target_staging" \
            mad_decoder_init mad_decoder_run mad_decoder_finish mad_stream_buffer
    fi

    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-aac "* ]]; then
        local faad_src
        make_run "$sdk_dir" package/feeds/packages/faad2/prepare NO_DEPS=1 -j"$jobs"
        faad_src="$(prepared_source_dir faad2)"
        mkdir -p "$target_staging/usr/include"
        copy_single_header "$faad_src" neaacdec.h "$target_staging/usr/include/neaacdec.h"
        stage_official_link_stub libfaad2 packages 'libfaad.so.*' libfaad.so "$target_staging" \
            NeAACDecOpen NeAACDecGetCurrentConfiguration NeAACDecSetConfiguration \
            NeAACDecInit NeAACDecDecode NeAACDecClose
    fi

    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-vorbis "* ]]; then
        local ogg_src vorbis_src
        make_run "$sdk_dir" package/feeds/packages/libogg/prepare NO_DEPS=1 -j"$jobs"
        make_run "$sdk_dir" package/feeds/packages/libvorbis/prepare NO_DEPS=1 -j"$jobs"
        ogg_src="$(prepared_source_dir libogg)"
        vorbis_src="$(prepared_source_dir libvorbis)"
        mkdir -p "$target_staging/usr/include/ogg" "$target_staging/usr/include/vorbis"
        cp -f "$ogg_src"/include/ogg/*.h "$target_staging/usr/include/ogg/"
        cp -f "$vorbis_src"/include/vorbis/*.h "$target_staging/usr/include/vorbis/"
        [[ -f "$target_staging/usr/include/vorbis/vorbisfile.h" ]] || {
            echo "ERROR: Vorbis headers were not staged." >&2
            exit 5
        }
        stage_official_link_stub libvorbis packages 'libvorbisfile.so.*' libvorbisfile.so "$target_staging" \
            ov_open_callbacks ov_read ov_info ov_clear
    fi

    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-opus "* ]]; then
        local opus_src opusfile_src
        make_run "$sdk_dir" package/feeds/packages/opus/prepare NO_DEPS=1 -j"$jobs"
        make_run "$sdk_dir" package/feeds/packages/opusfile/prepare NO_DEPS=1 -j"$jobs"
        opus_src="$(prepared_source_dir opus)"
        opusfile_src="$(prepared_source_dir opusfile)"
        mkdir -p "$target_staging/usr/include/opus"
        find "$opus_src/include" -maxdepth 1 -type f -name '*.h' -exec cp -f {} "$target_staging/usr/include/opus/" \;
        find "$opusfile_src/include" -maxdepth 1 -type f -name '*.h' -exec cp -f {} "$target_staging/usr/include/opus/" \;
        [[ -f "$target_staging/usr/include/opus/opusfile.h" ]] || {
            echo "ERROR: opusfile headers were not staged." >&2
            exit 5
        }
        stage_official_link_stub libopusfile packages 'libopusfile.so.*' libopusfile.so "$target_staging" \
            op_open_callbacks op_read_stereo op_free
    fi
}

prepare_hostap_sdk() {
    local -a target_staging_matches=()
    local target_staging libubox_src ubus_src ucode_src udebug_src mbedtls_src

    mapfile -t target_staging_matches < <(
        find "$sdk_dir/staging_dir" -mindepth 1 -maxdepth 1 -type d -name 'target-*' -print
    )
    [[ "${#target_staging_matches[@]}" -eq 1 ]] || {
        echo "ERROR: expected one target staging directory, found ${#target_staging_matches[@]}." >&2
        exit 5
    }
    target_staging="${target_staging_matches[0]}"

    # AudioWRT's multicall wpad needs these development interfaces, but the
    # firmware must keep
    # the exact official OpenWrt runtime packages. Compile only libnl-tiny
    # and libjson-c with NO_DEPS=1: libjson-c supplies the public headers pulled
    # in by libucode's headers, while the final image still resolves the official
    # libjson-c runtime transitively through libucode. Prepare the remaining
    # source trees for headers and link against build-only stubs generated from
    # the official release APKs instead of rebuilding ubus/ucode/udebug.
    make_run "$sdk_dir" \
        package/feeds/base/libnl-tiny/compile \
        package/feeds/base/libjson-c/compile \
        package/feeds/base/mbedtls/configure \
        package/feeds/base/libubox/prepare \
        package/feeds/base/ubus/prepare \
        package/feeds/base/ucode/prepare \
        package/feeds/base/udebug/prepare \
        NO_DEPS=1 -j"$jobs"

    libubox_src="$(prepared_source_dir libubox)"
    ubus_src="$(prepared_source_dir ubus)"
    ucode_src="$(prepared_source_dir ucode)"
    udebug_src="$(prepared_source_dir udebug)"
    mbedtls_src="$(prepared_source_dir mbedtls)"

    mkdir -p \
        "$target_staging/usr/include/libubox" \
        "$target_staging/usr/include/ucode" \
        "$target_staging/usr/include/mbedtls" \
        "$target_staging/usr/include/psa" \
        "$target_staging/usr/include"

    find "$libubox_src" -maxdepth 1 -type f -name '*.h' \
        -exec cp -f {} "$target_staging/usr/include/libubox/" \;
    find "$ubus_src" -maxdepth 1 -type f -name '*.h' \
        -exec cp -f {} "$target_staging/usr/include/" \;
    cp -f "$ucode_src"/include/ucode/*.h "$target_staging/usr/include/ucode/"
    find "$udebug_src" -maxdepth 1 -type f -name '*.h' \
        -exec cp -f {} "$target_staging/usr/include/" \;
    cp -f "$mbedtls_src"/include/mbedtls/*.h "$target_staging/usr/include/mbedtls/"
    cp -f "$mbedtls_src"/include/psa/*.h "$target_staging/usr/include/psa/"

    for header in \
        libubox/uloop.h \
        libubox/blobmsg_json.h \
        libubus.h \
        json-c/json.h \
        ucode/lib.h \
        udebug.h \
        mbedtls/ssl.h \
        mbedtls/mbedtls_config.h \
        psa/crypto.h; do
        [[ -f "$target_staging/usr/include/$header" ]] || {
            echo "ERROR: WPA SDK header was not staged: $header" >&2
            exit 5
        }
    done

    stage_official_link_stub libubox base 'libubox.so.*' libubox.so \
        "$target_staging" --all-dynamic-symbols
    stage_official_link_stub libblobmsg-json base 'libblobmsg_json.so.*' \
        libblobmsg_json.so "$target_staging" --all-dynamic-symbols
    stage_official_link_stub libubus base 'libubus.so.*' libubus.so \
        "$target_staging" --all-dynamic-symbols
    stage_official_link_stub libucode base 'libucode.so.*' libucode.so \
        "$target_staging" --all-dynamic-symbols
    stage_official_link_stub libudebug base 'libudebug.so*' libudebug.so \
        "$target_staging" --all-dynamic-symbols
    stage_official_link_stub libmbedtls21 base 'libmbedcrypto.so.*' libmbedcrypto.so \
        "$target_staging" --provider-name libmbedtls --all-dynamic-symbols
    stage_official_link_stub libmbedtls21 base 'libmbedx509.so.*' libmbedx509.so \
        "$target_staging" --provider-name libmbedtls --all-dynamic-symbols
    stage_official_link_stub libmbedtls21 base 'libmbedtls.so.*' libmbedtls.so \
        "$target_staging" --provider-name libmbedtls --all-dynamic-symbols
}

# Keep the SDK's official exact-release feed configuration intact. We only
# update the feeds whose source trees are needed by AudioWRT package Makefiles:
# packages (for shared build helpers such as rust-package.mk) and audiowrt.
# Update base lazily only when source-build dependencies need it.
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
download_file "$version_buildinfo_url" "$official_version_buildinfo"

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

native_player_sdk=0
hostap_sdk=0
if [[ " ${firmware_packages[*]} " == *" libaudiowrt-player "* ||
      " ${firmware_packages[*]} " == *" audiowrt-player-flac "* ||
      " ${firmware_packages[*]} " == *" audiowrt-player-mp3 "* ||
      " ${firmware_packages[*]} " == *" audiowrt-player-aac "* ||
      " ${firmware_packages[*]} " == *" audiowrt-player-wav "* ||
      " ${firmware_packages[*]} " == *" audiowrt-player-vorbis "* ||
      " ${firmware_packages[*]} " == *" audiowrt-player-opus "* ]]; then
    native_player_sdk=1
fi
# The constrained AudioWRT Wi-Fi provider is one multicall wpad binary built
# from the exact OpenWrt hostap source. Stage its development interfaces once
# without turning OpenWrt runtime dependencies into source-build roots.
if [[ " ${firmware_packages[*]} " == *" audiowrt-wpad "* ]]; then
    hostap_sdk=1
fi

if (( native_player_sdk )); then
    register_official_sdk_source base libs/libubox
    register_official_sdk_source base libs/uclient
    register_official_sdk_source base libs/ustream-ssl


    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-flac "* ]]; then
        register_official_sdk_source packages libs/flac
    fi
    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-mp3 "* ]]; then
        register_official_sdk_source packages libs/libmad
    fi
    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-aac "* ]]; then
        register_official_sdk_source packages libs/faad2
    fi
    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-vorbis "* ]]; then
        register_official_sdk_source packages libs/libogg
        register_official_sdk_source packages libs/libvorbis
    fi
    if [[ " ${firmware_packages[*]} " == *" audiowrt-player-opus "* ]]; then
        register_official_sdk_source packages libs/opus
        register_official_sdk_source packages libs/opusfile
    fi
fi

if (( hostap_sdk )); then
    register_official_sdk_source base libs/libnl-tiny
    register_official_sdk_source base libs/libjson-c
    register_official_sdk_source base libs/mbedtls
    register_official_sdk_source base libs/libubox
    register_official_sdk_source base system/ubus
    register_official_sdk_source base utils/ucode
    register_official_sdk_source base libs/udebug
fi

if [[ " ${firmware_packages[*]} " == *" kmod-audiowrt-bluetooth "* ]]; then
    prepare_bluetooth_package
fi

# Register all AudioWRT target source directories so the resolver can see the
# complete package graph. Only explicitly required source-build dependencies
# are installed through the official feed installer below.
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
done < "$repo_root/config/build/package-build-targets"

# Select only the AudioWRT-owned firmware roots requested by the resolved
# profile. The SDK's shipped package selections are not AudioWRT build intent.
for package in "${firmware_packages[@]}"; do
    if awk -F '|' -v package="$package" '$0 !~ /^[[:space:]]*#/ && $1 == package { found=1 } END { exit found ? 0 : 1 }' "$repo_root/config/build/package-build-targets"; then
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
# requested firmware roots. AudioWRT source packages such as librespot and
# bluez-alsa are included only when the selected package groups require them.
python3 "$repo_root/scripts/resolve-package-build-targets.py" \
    "$repo_root/config/build/package-build-targets" \
    "$packageinfo" \
    "${firmware_packages[@]}" \
    --providers "${profile_firmware_packages[@]}" > "$build_plan"

mapfile -t build_specs < "$build_plan"
[[ "${#build_specs[@]}" -gt 0 ]] || {
    echo "ERROR: no AudioWRT SDK build targets were selected." >&2
    exit 5
}

declare -A source_build_package=()
while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    source_build_package["$package"]=1
done < <(read_package_file "$repo_root/config/build/source-build-packages")

build_packages=()
package_only_packages=()
package_only_targets=()
source_packages=()
source_targets=()
declare -A package_only_target_seen=()
declare -A source_target_seen=()

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
        if [[ -z "${source_target_seen[$target_path]+x}" ]]; then
            source_targets+=("$target_path")
            source_target_seen["$target_path"]=1
        fi
    else
        package_only_packages+=("$package")
        if [[ -z "${package_only_target_seen[$target_path]+x}" ]]; then
            package_only_targets+=("$target_path")
            package_only_target_seen["$target_path"]=1
        fi
    fi
done

# A single SDK target can emit multiple AudioWRT packages. If any package from
# that target is an explicit source root (for example audiowrt-bluez while
# audiowrt-bluez-libs is another output of the same recipe), compile the target
# exactly once through the source path and remove it from the NO_DEPS target set.
if [[ "${#package_only_targets[@]}" -gt 0 && "${#source_targets[@]}" -gt 0 ]]; then
    filtered_package_only_targets=()
    for target_path in "${package_only_targets[@]}"; do
        if [[ -n "${source_target_seen[$target_path]+x}" ]]; then
            continue
        fi
        filtered_package_only_targets+=("$target_path")
    done
    package_only_targets=("${filtered_package_only_targets[@]}")
fi

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
        "$repo_root/config/build/package-build-targets" \
        "$packageinfo" \
        "${source_packages[@]}" \
        --providers "${build_packages[@]}" > "$source_dependencies_file"
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

# The SDK may omit a package symbol when its official runtime dependency source
# is not installed. Pass the selected package symbols directly to each target;
# OpenWrt still writes the original DEPENDS metadata into the APK, while NO_DEPS
# prevents these runtime packages from being built from source.
package_config_args=()
for package in "${build_packages[@]}"; do
    package_config_args+=("CONFIG_PACKAGE_${package}=m")
done

# The SDK ships the target toolchain itself, but package dependency checking
# needs its libc/libgcc package metadata staged before NO_DEPS packages are
# emitted. Build this metadata once instead of letting every AudioWRT package
# traverse package/toolchain as a dependency.
make_run "$sdk_dir" package/toolchain/compile NO_DEPS=1 -j"$jobs"

if (( native_player_sdk )); then
    prepare_native_player_sdk
fi
if (( hostap_sdk )); then
    prepare_hostap_sdk
fi

# Download every selected AudioWRT target without traversing dependencies. Source
# packages download their own upstream tarballs here; development dependencies
# are staged separately below and runtime-only dependencies stay official.
ordered_targets=()
declare -A ordered_target_seen=()
for spec in "${build_specs[@]}"; do
    target_path="${spec#*|}"
    if [[ -z "${ordered_target_seen[$target_path]+x}" ]]; then
        ordered_targets+=("$target_path")
        ordered_target_seen["$target_path"]=1
    fi
done

download_targets=()
for target_path in "${ordered_targets[@]}"; do
    download_targets+=("${target_path%/compile}/download")
done
if [[ "${#download_targets[@]}" -gt 0 ]]; then
    make_run "$sdk_dir" "${package_config_args[@]}" "${download_targets[@]}" NO_DEPS=1 -j"$jobs"
fi

# Compile in the topological order emitted by resolve-package-build-targets.py.
# Package-only AudioWRT targets stay behind NO_DEPS=1. Genuine upstream source
# targets may use the explicitly registered development dependencies, but they
# run only after earlier AudioWRT providers (for example minimal ALSA and SBC)
# have installed their Build/InstallDev output into the SDK staging directory.
for target_path in "${ordered_targets[@]}"; do
    target_roots=()
    for spec in "${build_specs[@]}"; do
        [[ "${spec#*|}" == "$target_path" ]] || continue
        target_roots+=("${spec%%|*}")
    done
    [[ "${#target_roots[@]}" -gt 0 ]] || {
        echo "ERROR: no AudioWRT packages map to SDK target $target_path." >&2
        exit 5
    }

    target_build_plan="$work_dir/target-build-plan.txt"
    python3 "$repo_root/scripts/resolve-package-build-targets.py" \
        "$repo_root/config/build/package-build-targets" \
        "$packageinfo" \
        "${target_roots[@]}" \
        --providers "${build_packages[@]}" > "$target_build_plan"
    mapfile -t target_build_specs < "$target_build_plan"
    declare -A target_package_seen=()
    for spec in "${target_build_specs[@]}"; do
        target_package_seen["${spec%%|*}"]=1
    done

    target_package_config_args=()
    for package in "${build_packages[@]}"; do
        if [[ -n "${target_package_seen[$package]+x}" ]]; then
            target_package_config_args+=("CONFIG_PACKAGE_${package}=m")
        else
            target_package_config_args+=("CONFIG_PACKAGE_${package}=n")
        fi
    done

    if [[ -n "${source_target_seen[$target_path]+x}" ]]; then
        # BlueZ's official bluez-libs runtime dependency pulls kmod-bluetooth
        # on USB targets. AudioWRT supplies the exact-release module APKs, so
        # compiling userspace source targets must not build the SDK kernel or
        # either official/custom Bluetooth module package. Keep the selected
        # AudioWRT userspace symbols enabled: later source targets depend on
        # providers built earlier (for example bluez-alsa on audiowrt-bluez).
        target_package_config_args+=("CONFIG_PACKAGE_kmod-bluetooth=n")
        target_package_config_args+=("CONFIG_PACKAGE_kmod-audiowrt-bluetooth=n")
        make_run "$sdk_dir" "${target_package_config_args[@]}" "$target_path" -j"$jobs"
    else
        make_run "$sdk_dir" "${target_package_config_args[@]}" "$target_path" NO_DEPS=1 -j"$jobs"
    fi
done

rm -rf "$local_apks_dir"
mkdir -p "$local_apks_dir"

# All APKs produced by the reusable AudioWRT feed are ours. Userspace feed
# packages are emitted under bin/packages, while kernel packages can be emitted
# under the target-specific package directory. Copy both classes so every
# selected AudioWRT package is visible to the ImageBuilder.
while IFS= read -r -d '' apk; do
    cp -f "$apk" "$local_apks_dir/"
done < <(
    find "$sdk_dir/bin/packages" -type f -path '*/audiowrt/*.apk' -print0 2>/dev/null || true
    find "$sdk_dir/bin/targets/$target/$subtarget/packages" \
        -type f -name 'kmod-audiowrt-*.apk' -print0 2>/dev/null || true
)

local_apk_count="$(find "$local_apks_dir" -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d ' ')"
[[ "$local_apk_count" -gt 0 ]] || {
    echo "ERROR: SDK build did not produce AudioWRT APKs." >&2
    exit 6
}

for package in "${build_packages[@]}"; do
    if ! compgen -G "$local_apks_dir/${package}-*.apk" > /dev/null; then
        echo "ERROR: SDK build did not produce selected AudioWRT package: $package" >&2
        exit 6
    fi
done

if [[ "$build_mode" == "packages" ]]; then
    mkdir -p "$output_dir/packages"
    cp -f "$local_apks_dir"/*.apk "$output_dir/packages/"
    cp "$platform_metadata" "$output_dir/platform.json"
    cp "$resolved_profile" "$output_dir/audiowrt-profile.json"
    cp "$artifacts_metadata" "$output_dir/openwrt-artifacts.json"
    cp "$sdk_dir/feeds.conf" "$output_dir/sdk-feeds.conf"
    cp "$official_feeds_buildinfo" "$output_dir/official-feeds.buildinfo"
    cp "$official_version_buildinfo" "$output_dir/official-version.buildinfo"
    cp "$registered_sources" "$output_dir/sdk-audiowrt-sources.txt"
    cp "$source_dependencies_file" "$output_dir/source-build-dependencies.txt"
    cp "$repo_root/config/build/package-build-targets" "$output_dir/package-build-targets"
    cp "$repo_root/config/build/source-build-packages" "$output_dir/source-build-packages"
    cp "$build_plan" "$output_dir/package-build-plan.txt"
    [[ -f "$sdk_dir/.config" ]] && cp "$sdk_dir/.config" "$output_dir/sdk.config"

    audiowrt_commit="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf unknown)"
    cache_enabled='no'
    [[ -n "$cache_dir" ]] && cache_enabled='yes'
    cat > "$output_dir/BUILD_INFO" <<EOF
BUILD_MODE=exact-release-sdk-packages
AUDIOWRT_VERSION=$audiowrt_version
BUILDER_IMAGE=$builder_image
PLATFORM=$platform
AUDIOWRT_PROFILE=$audiowrt_profile
AUDIOWRT_PACKAGE_SELECTION=$package_request
AUDIOWRT_PACKAGE_GROUPS=$profile_package_groups
TARGET=$target
SUBTARGET=$subtarget
OPENWRT_RESOLVED_REF=$resolved_release
OPENWRT_SOURCE=$openwrt_source
OPENWRT_VERSION=$openwrt_version
OPENWRT_COMMIT=$openwrt_commit
SDK_URL=$sdk_url
SDK_FEEDS_CONFIG=official-sdk-default+audiowrt
SDK_PACKAGE_ONLY_MODE=NO_DEPS
AUDIOWRT_COMMIT=$audiowrt_commit
AUDIOWRT_PACKAGES_REPOSITORY=$packages_repo
AUDIOWRT_PACKAGES_REF=$packages_ref
AUDIOWRT_PACKAGES_COMMIT=$audiowrt_packages_commit
AUDIOWRT_BUILD_PACKAGES=${build_packages[*]}
AUDIOWRT_PACKAGE_ONLY_PACKAGES=${package_only_packages[*]}
AUDIOWRT_SOURCE_PACKAGES=${source_packages[*]}
SOURCE_BUILD_DEPENDENCIES=${source_dependencies[*]}
LOCAL_APKS=$local_apk_count
VERBOSITY=$verbosity
CACHE_ENABLED=$cache_enabled
EOF

    python3 - "$platform_metadata" "$artifacts_metadata" "$resolved_profile" "$output_dir/manifest.json" <<PY
import json, sys
platform_data = json.load(open(sys.argv[1], encoding="utf-8"))
artifacts = json.load(open(sys.argv[2], encoding="utf-8"))
profile_data = json.load(open(sys.argv[3], encoding="utf-8"))
manifest = {
    "build_mode": "exact-release-sdk-packages",
    "audiowrt_version": "$audiowrt_version",
    "builder_image": "$builder_image",
    "audiowrt_commit": "$audiowrt_commit",
    "audiowrt_packages_repository": "$packages_repo",
    "audiowrt_packages_ref": "$packages_ref",
    "audiowrt_packages_commit": "$audiowrt_packages_commit",
    "audiowrt_profile": "$audiowrt_profile",
    "package_selection": "$package_request",
    "package_groups": profile_data["package_groups"],
    "resolved_profile": profile_data,
    "openwrt_repository": "$openwrt_repo",
    "openwrt_source": "$openwrt_source",
    "openwrt_version": "$openwrt_version",
    "openwrt_resolved_ref": "$resolved_release",
    "openwrt_commit": "$openwrt_commit",
    "openwrt_artifacts": artifacts,
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

    printf '\nAudioWRT package build complete.\nArtifacts: %s\n' "$output_dir"
    find "$output_dir/packages" -maxdepth 1 -type f -name '*.apk' -printf '  %f\n' | sort
    exit 0
fi

# Assemble the final firmware from the official ImageBuilder for the same exact
# release. OpenWrt runtime dependencies are resolved from the official release
# repositories; only locally built AudioWRT APKs are injected.
imagebuilder_dir="$(extract_archive "$imagebuilder_url" "$work_dir/imagebuilder" "ImageBuilder")"
imagebuilder_config="$imagebuilder_dir/.config"

# AudioWRT treats /var as volatile runtime storage. Reject any OpenWrt target
# that was built with persistent /var, because upstream services may write
# generated configs, PID/state files or caches below /var during normal use.
if grep -q "^CONFIG_TARGET_ROOTFS_PERSIST_VAR=y$" "$imagebuilder_config"; then
    die "AudioWRT requires volatile /var; CONFIG_TARGET_ROOTFS_PERSIST_VAR=y is not supported"
fi
mkdir -p "$imagebuilder_dir/packages"
cp -f "$local_apks_dir"/*.apk "$imagebuilder_dir/packages/"

package_args=()
while IFS= read -r package; do package_args+=("$package"); done < <(read_package_file "$packages_add_file")
while IFS= read -r package; do package_args+=("-$package"); done < <(read_package_file "$packages_remove_file")
package_string="${package_args[*]}"

image_defaults_dir="$work_dir/image-defaults"
rm -rf "$image_defaults_dir"
python3 "$repo_root/scripts/prepare-image-defaults.py" \
    "$packages_add_file" "$sdk_dir/feeds/audiowrt" "$image_defaults_dir"

image_args=(
    "FILES=$image_defaults_dir"
    "PROFILE=$platform"
    "PACKAGES=$package_string"
    "BIN_DIR=$output_dir"
)
if [[ "$squashfs_block_size" != "default" ]]; then
    if grep -q '^CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=' "$imagebuilder_config"; then
        sed -i "s/^CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=.*/CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=$squashfs_block_size/" "$imagebuilder_config"
    else
        printf 'CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=%s\n' "$squashfs_block_size" >> "$imagebuilder_config"
    fi
fi

make_run "$imagebuilder_dir" image "${image_args[@]}"

cp "$platform_metadata" "$output_dir/platform.json"
cp "$resolved_profile" "$output_dir/audiowrt-profile.json"
cp "$artifacts_metadata" "$output_dir/openwrt-artifacts.json"
cp "$sdk_dir/feeds.conf" "$output_dir/sdk-feeds.conf"
cp "$official_feeds_buildinfo" "$output_dir/official-feeds.buildinfo"
cp "$official_version_buildinfo" "$output_dir/official-version.buildinfo"
cp "$registered_sources" "$output_dir/sdk-audiowrt-sources.txt"
cp "$source_dependencies_file" "$output_dir/source-build-dependencies.txt"
cp "$packages_add_file" "$output_dir/audiowrt-packages.add"
cp "$packages_remove_file" "$output_dir/audiowrt-packages.remove"
cp "$repo_root/config/build/package-build-targets" "$output_dir/package-build-targets"
cp "$repo_root/config/build/source-build-packages" "$output_dir/source-build-packages"
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
AUDIOWRT_VERSION=$audiowrt_version
BUILDER_IMAGE=$builder_image
PLATFORM=$platform
AUDIOWRT_PROFILE=$audiowrt_profile
AUDIOWRT_PACKAGE_GROUPS=$profile_package_groups
TARGET=$target
SUBTARGET=$subtarget
OPENWRT_RESOLVED_REF=$resolved_release
OPENWRT_SOURCE=$openwrt_source
OPENWRT_VERSION=$openwrt_version
OPENWRT_COMMIT=$openwrt_commit
SDK_URL=$sdk_url
IMAGEBUILDER_URL=$imagebuilder_url
OFFICIAL_FEEDS_BUILDINFO=$feeds_buildinfo_url
OFFICIAL_VERSION_BUILDINFO=$version_buildinfo_url
SDK_FEEDS_CONFIG=official-sdk-default+audiowrt
SDK_PACKAGE_ONLY_MODE=NO_DEPS
AUDIOWRT_COMMIT=$audiowrt_commit
AUDIOWRT_PACKAGES_REPOSITORY=$packages_repo
AUDIOWRT_PACKAGES_REF=$packages_ref
AUDIOWRT_PACKAGES_COMMIT=$audiowrt_packages_commit
AUDIOWRT_BUILD_PACKAGES=${build_packages[*]}
AUDIOWRT_PACKAGE_ONLY_PACKAGES=${package_only_packages[*]}
AUDIOWRT_SOURCE_PACKAGES=${source_packages[*]}
SOURCE_BUILD_DEPENDENCIES=${source_dependencies[*]}
LOCAL_APKS=$local_apk_count
VERBOSITY=$verbosity
CACHE_ENABLED=$cache_enabled
EOF

python3 - "$platform_metadata" "$artifacts_metadata" "$resolved_profile" "$output_dir/manifest.json" <<PY
import json, sys
platform_data = json.load(open(sys.argv[1], encoding="utf-8"))
artifacts = json.load(open(sys.argv[2], encoding="utf-8"))
profile_data = json.load(open(sys.argv[3], encoding="utf-8"))
manifest = {
    "build_mode": "exact-release-sdk-imagebuilder",
    "audiowrt_version": "$audiowrt_version",
    "builder_image": "$builder_image",
    "audiowrt_commit": "$audiowrt_commit",
    "audiowrt_packages_repository": "$packages_repo",
    "audiowrt_packages_ref": "$packages_ref",
    "audiowrt_packages_commit": "$audiowrt_packages_commit",
    "audiowrt_profile": "$audiowrt_profile",
    "package_groups": profile_data["package_groups"],
    "resolved_profile": profile_data,
    "openwrt_repository": "$openwrt_repo",
    "openwrt_source": "$openwrt_source",
    "openwrt_version": "$openwrt_version",
    "openwrt_resolved_ref": "$resolved_release",
    "openwrt_commit": "$openwrt_commit",
    "openwrt_artifacts": artifacts,
    "sdk_feeds_config": "official-sdk-default+audiowrt",
    "sdk_package_only_mode": "NO_DEPS",
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
