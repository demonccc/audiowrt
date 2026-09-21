#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_script="$repo_root/scripts/build.sh"

if grep -Fq 'make_run "$sdk_dir" package/download' "$build_script"; then
    echo "ERROR: build.sh must not invoke the SDK-wide package/download target." >&2
    exit 1
fi

if grep -Fq './scripts/feeds install "${feed_install_packages[@]}"' "$build_script"; then
    echo "ERROR: package-only AudioWRT packages must not recursively install runtime feed dependencies." >&2
    exit 1
fi

grep -Fq 'prepare_hostap_sdk()' "$build_script" || {
    echo "ERROR: hostap-derived AudioWRT binaries must share one SDK staging path." >&2
    exit 1
}
grep -Fq 'audiowrt-wpad' "$build_script" || {
    echo "ERROR: AudioWRT wpad must trigger hostap SDK staging." >&2
    exit 1
}
grep -Fq 'register_official_sdk_source base libs/mbedtls' "$build_script" || {
    echo "ERROR: wpad must use headers from the official OpenWrt mbedTLS source." >&2
    exit 1
}
grep -Fq 'package/feeds/base/mbedtls/configure' "$build_script" || {
    echo "ERROR: official mbedTLS headers must be configured without producing a custom runtime package." >&2
    exit 1
}
grep -Fq 'stage_official_link_stub libmbedtls21 base' "$build_script" || {
    echo "ERROR: wpad must link against the official OpenWrt libmbedtls21 runtime ABI." >&2
    exit 1
}

grep -Fq './scripts/feeds update packages audiowrt' "$build_script" || {
    echo "ERROR: core builds must update the package-helper and AudioWRT feeds." >&2
    exit 1
}

grep -Fq 'register_official_sdk_source base libs/libubox' "$build_script" || {
    echo "ERROR: native player builds must register libubox headers without compiling libubox." >&2
    exit 1
}
grep -Fq 'register_official_sdk_source base libs/uclient' "$build_script" || {
    echo "ERROR: native player builds must register uclient headers without compiling uclient." >&2
    exit 1
}
grep -Fq 'stage_official_link_stub libuclient base' "$build_script" || {
    echo "ERROR: native player builds must link against an SDK-only libuclient stub." >&2
    exit 1
}
grep -Fq 'stage_official_link_stub libflac packages' "$build_script" || {
    echo "ERROR: FLAC builds must link against an SDK-only libflac stub." >&2
    exit 1
}
grep -Fq 'stage_official_link_stub libmad packages' "$build_script" || {
    echo "ERROR: MP3 builds must link against an SDK-only libmad stub." >&2
    exit 1
}
grep -Fq 'stage_official_link_stub libfaad2 packages' "$build_script" || {
    echo "ERROR: AAC builds must link against an SDK-only libfaad2 stub." >&2
    exit 1
}
grep -Fq 'stage_official_link_stub libvorbis packages' "$build_script" || {
    echo "ERROR: Vorbis builds must link against an SDK-only libvorbisfile stub." >&2
    exit 1
}
grep -Fq 'Runtime APK libraries are aggressively stripped by OpenWrt' "$build_script" || {
    echo "ERROR: stripped runtime libraries must not be copied into the SDK linker path." >&2
    exit 1
}

grep -Fq "grep '/toolchain-[^/]*/bin/[^/]*-readelfgrep -Fq 'ln -sf "$linker_name" "$target_staging/usr/lib/$soname"' "$build_script" || {
    echo "ERROR: SDK link stubs must expose their runtime SONAME for transitive links." >&2
    exit 1
}
grep -Fq 'uloop_cancelled uloop_init uloop_run_timeout uloop_done' "$build_script" || {
    echo "ERROR: libubox stub must satisfy uloop inline-helper symbols." >&2
    exit 1
}
if grep -Eq 'package/feeds/(base|packages)/(libubox|uclient|ustream-ssl|flac|libmad|faad2|libogg|libvorbis)/compile' "$build_script"; then
    echo "ERROR: official native-player dependencies must not be compiled." >&2
    exit 1
fi

grep -Fq 'make_run "$sdk_dir" package/toolchain/compile NO_DEPS=1 -j"$jobs"' "$build_script" || {
    echo "ERROR: SDK toolchain package metadata must be staged once before NO_DEPS builds." >&2
    exit 1
}

grep -Fq 'make_run "$sdk_dir" "${download_targets[@]}" NO_DEPS=1 -j"$jobs"' "$build_script" || {
    echo "ERROR: all selected package downloads must use NO_DEPS=1." >&2
    exit 1
}

grep -Fq 'for target_path in "${ordered_targets[@]}"; do' "$build_script" || {
    echo "ERROR: AudioWRT compile targets must preserve topological build-plan order." >&2
    exit 1
}
grep -Fq 'if [[ -n "${source_target_seen[$target_path]+x}" ]]; then' "$build_script" || {
    echo "ERROR: ordered builds must distinguish genuine source targets." >&2
    exit 1
}
grep -Fq 'make_run "$sdk_dir" "$target_path" NO_DEPS=1 -j"$jobs"' "$build_script" || {
    echo "ERROR: package-only compile targets must use NO_DEPS=1." >&2
    exit 1
}
grep -Fq 'make_run "$sdk_dir" "$target_path" -j"$jobs"' "$build_script" || {
    echo "ERROR: genuine AudioWRT source packages must keep their explicit development dependency path." >&2
    exit 1
}
grep -Fq -- '--providers "${build_packages[@]}"' "$build_script" || {
    echo "ERROR: source dependency resolution must honor selected AudioWRT providers." >&2
    exit 1
}

grep -Fq 'declare -A source_target_seen=()' "$build_script" || {
    echo "ERROR: split packages must not compile the same source target repeatedly." >&2
    exit 1
}

grep -Fq 'config/build/source-build-packages' "$build_script" || {
    echo "ERROR: build.sh must classify genuine source builds through config/build/source-build-packages." >&2
    exit 1
}

grep -qx 'audiowrt-btctl' "$repo_root/config/build/source-build-packages" || {
    echo "ERROR: audiowrt-btctl must use the development-dependency path for glib2/GIO headers." >&2
    exit 1
}

grep -Fq 'source_target_seen[$target_path]' "$build_script" || {
    echo "ERROR: shared SDK targets must be de-duplicated in favor of the source-build path." >&2
    exit 1
}

printf 'SDK package-only build boundary test passed.\n'
" "$build_script" || {
    echo "ERROR: runtime link stubs must resolve readelf only from a target toolchain." >&2
    exit 1
}
grep -Fq 'paired_cc="${candidate%readelf}gcc"' "$build_script" || {
    echo "ERROR: target readelf selection must require a matching target gcc." >&2
    exit 1
}
if grep -Fq "find \"$sdk_dir/staging_dir\" -path '*/bin/*-readelf'" "$build_script"; then
    echo "ERROR: broad SDK readelf discovery can select host helpers such as mklibs-readelf." >&2
    exit 1
fi
grep -Fq 'ln -sf "$linker_name" "$target_staging/usr/lib/$soname"' "$build_script" || {
    echo "ERROR: SDK link stubs must expose their runtime SONAME for transitive links." >&2
    exit 1
}
grep -Fq 'uloop_cancelled uloop_init uloop_run_timeout uloop_done' "$build_script" || {
    echo "ERROR: libubox stub must satisfy uloop inline-helper symbols." >&2
    exit 1
}
if grep -Eq 'package/feeds/(base|packages)/(libubox|uclient|ustream-ssl|flac|libmad|faad2|libogg|libvorbis)/compile' "$build_script"; then
    echo "ERROR: official native-player dependencies must not be compiled." >&2
    exit 1
fi

grep -Fq 'make_run "$sdk_dir" package/toolchain/compile NO_DEPS=1 -j"$jobs"' "$build_script" || {
    echo "ERROR: SDK toolchain package metadata must be staged once before NO_DEPS builds." >&2
    exit 1
}

grep -Fq 'make_run "$sdk_dir" "${download_targets[@]}" NO_DEPS=1 -j"$jobs"' "$build_script" || {
    echo "ERROR: all selected package downloads must use NO_DEPS=1." >&2
    exit 1
}

grep -Fq 'for target_path in "${ordered_targets[@]}"; do' "$build_script" || {
    echo "ERROR: AudioWRT compile targets must preserve topological build-plan order." >&2
    exit 1
}
grep -Fq 'if [[ -n "${source_target_seen[$target_path]+x}" ]]; then' "$build_script" || {
    echo "ERROR: ordered builds must distinguish genuine source targets." >&2
    exit 1
}
grep -Fq 'make_run "$sdk_dir" "$target_path" NO_DEPS=1 -j"$jobs"' "$build_script" || {
    echo "ERROR: package-only compile targets must use NO_DEPS=1." >&2
    exit 1
}
grep -Fq 'make_run "$sdk_dir" "$target_path" -j"$jobs"' "$build_script" || {
    echo "ERROR: genuine AudioWRT source packages must keep their explicit development dependency path." >&2
    exit 1
}
grep -Fq -- '--providers "${build_packages[@]}"' "$build_script" || {
    echo "ERROR: source dependency resolution must honor selected AudioWRT providers." >&2
    exit 1
}

grep -Fq 'declare -A source_target_seen=()' "$build_script" || {
    echo "ERROR: split packages must not compile the same source target repeatedly." >&2
    exit 1
}

grep -Fq 'config/build/source-build-packages' "$build_script" || {
    echo "ERROR: build.sh must classify genuine source builds through config/build/source-build-packages." >&2
    exit 1
}

grep -qx 'audiowrt-btctl' "$repo_root/config/build/source-build-packages" || {
    echo "ERROR: audiowrt-btctl must use the development-dependency path for glib2/GIO headers." >&2
    exit 1
}

grep -Fq 'source_target_seen[$target_path]' "$build_script" || {
    echo "ERROR: shared SDK targets must be de-duplicated in favor of the source-build path." >&2
    exit 1
}

printf 'SDK package-only build boundary test passed.\n'
