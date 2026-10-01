#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
profile="${AUDIOWRT_PROFILE:-tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5}"
channel="${AUDIOWRT_PACKAGES_CHANNEL:-stable}"
repository_base="${AUDIOWRT_PACKAGES_BASE_URL:-https://demonccc.github.io/audiowrt-packages}"
provisioning_ip="${AUDIOWRT_PROVISIONING_IP:-192.168.77.1}"
cache_dir="${CACHE_DIR:-}"
builder_image="demonccc/openwrt-builder:latest"

[[ "${AUDIOWRT_IN_CONTAINER:-0}" == 1 ]] || {
    echo "ERROR: scripts/build-firmware.sh is an internal container entry point." >&2
    exit 2
}
case "$channel" in stable|testing) ;; *) echo "ERROR: AUDIOWRT_PACKAGES_CHANNEL must be stable or testing." >&2; exit 2 ;; esac

json_field() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]])' "$1" "$2"
}

download_file() {
    local url="$1" destination="$2"
    mkdir -p "$(dirname "$destination")"
    echo "Downloading: $url"
    python3 - "$url" "$destination" <<'PY'
import shutil, sys, urllib.request
request = urllib.request.Request(sys.argv[1], headers={"User-Agent": "AudioWRT-builder"})
with urllib.request.urlopen(request) as response, open(sys.argv[2], "wb") as handle:
    shutil.copyfileobj(response, handle)
PY
}

prepare_archive() {
    local url="$1" destination="$2" label="$3"
    local archive temporary digest filename
    filename="$(basename "${url%%\?*}")"
    if [[ -n "$cache_dir" ]]; then
        mkdir -p "$cache_dir/archives"
        digest="$(printf '%s' "$url" | sha256sum | awk '{print substr($1,1,20)}')"
        archive="$cache_dir/archives/$digest/$filename"
        mkdir -p "$(dirname "$archive")"
        if [[ -s "$archive" ]]; then
            echo "Cache hit for $label: $archive" >&2
            printf '%s\n' "$archive"
            return
        fi
    else
        archive="$destination/$filename"
    fi
    temporary="${archive}.part"
    rm -f "$temporary"
    download_file "$url" "$temporary" >&2
    mv "$temporary" "$archive"
    printf '%s\n' "$archive"
}

extract_archive() {
    local url="$1" destination="$2" label="$3"
    rm -rf "$destination"
    mkdir -p "$destination/extract"
    local archive
    archive="$(prepare_archive "$url" "$destination" "$label")"
    tar --zstd -xf "$archive" -C "$destination/extract"
    mapfile -t roots < <(find "$destination/extract" -mindepth 1 -maxdepth 1 -type d -print)
    [[ "${#roots[@]}" -eq 1 ]] || { echo "ERROR: cannot determine extracted $label root." >&2; exit 4; }
    printf '%s\n' "${roots[0]}"
}

work_dir="$repo_root/.work/$profile"
output_dir="$repo_root/output/$profile"
resolved_profile="$work_dir/audiowrt-profile.json"
packages_add_file="$work_dir/resolved-packages.add"
packages_remove_file="$work_dir/resolved-packages.remove"
artifacts_metadata="$work_dir/openwrt-artifacts.json"
repository_metadata="$work_dir/package-repository.json"
local_apks="$work_dir/published-apks"
image_defaults="$work_dir/image-defaults"

rm -rf "$work_dir" "$output_dir"
mkdir -p "$work_dir" "$output_dir" "$local_apks"

python3 "$repo_root/scripts/resolve-audiowrt-profile.py" \
    "$repo_root/profiles" "$repo_root/config/package-groups" "$profile" > "$resolved_profile"

platform="$(json_field "$resolved_profile" openwrt_profile)"
openwrt_source="$(json_field "$resolved_profile" openwrt_source)"
openwrt_version="$(json_field "$resolved_profile" openwrt_version)"
target="$(json_field "$resolved_profile" target)"
subtarget="$(json_field "$resolved_profile" subtarget)"
squashfs_block_size="$(json_field "$resolved_profile" squashfs_block_size)"

[[ "$openwrt_source" == release ]] || {
    echo "ERROR: published AudioWRT package repositories currently support exact OpenWrt releases only." >&2
    exit 2
}
resolved_release="$(bash "$repo_root/scripts/resolve-openwrt-ref.sh" "$openwrt_version")"
release="${resolved_release#v}"

python3 - "$resolved_profile" "$packages_add_file" "$packages_remove_file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for key, path in (("packages_add", sys.argv[2]), ("packages_remove", sys.argv[3])):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(data[key]) + "\n")
PY

python3 "$repo_root/scripts/resolve-openwrt-artifacts.py" "$release" "$target" "$subtarget" > "$artifacts_metadata"
imagebuilder_url="$(json_field "$artifacts_metadata" imagebuilder_url)"
repository_url="${repository_base%/}/${channel}/${openwrt_version}/${target}/${subtarget}/repository.json"
download_file "$repository_url" "$repository_metadata"

python3 - "$repository_metadata" "$channel" "$openwrt_version" "$target" "$subtarget" <<'PY'
import json, sys
p, channel, version, target, subtarget = sys.argv[1:]
data = json.load(open(p, encoding="utf-8"))
expected = {
    "channel": channel,
    "openwrt_version": version,
    "target": target,
    "subtarget": subtarget,
}
for key, value in expected.items():
    if str(data.get(key)) != value:
        raise SystemExit(f"ERROR: package repository {key} mismatch: expected {value}, got {data.get(key)}")
if not data.get("packages"):
    raise SystemExit("ERROR: package repository contains no packages")
PY

repository_revision="$(json_field "$repository_metadata" revision)"
repository_sha256="$(sha256sum "$repository_metadata" | awk '{print $1}')"
architecture="$(json_field "$repository_metadata" architecture)"

printf 'AudioWRT firmware build\n'
printf '  Profile: %s\n' "$profile"
printf '  OpenWrt: %s (%s/%s)\n' "$openwrt_version" "$target" "$subtarget"
printf '  Package channel: %s\n' "$channel"
printf '  Package repository: %s\n' "$repository_url"
printf '  Repository revision: %s\n' "$repository_revision"
printf '  Architecture: %s\n' "$architecture"
printf '  ImageBuilder: %s\n' "$imagebuilder_url"

python3 - "$repository_metadata" "$local_apks" <<'PY'
import hashlib, json, pathlib, shutil, sys, urllib.request
metadata = json.load(open(sys.argv[1], encoding="utf-8"))
out = pathlib.Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
for name, package in sorted(metadata["packages"].items()):
    destination = out / package["filename"]
    print(f"Downloading AudioWRT package: {name} -> {package['url']}")
    request = urllib.request.Request(package["url"], headers={"User-Agent": "AudioWRT-builder"})
    with urllib.request.urlopen(request) as response, destination.open("wb") as handle:
        shutil.copyfileobj(response, handle)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    if digest != package["sha256"]:
        raise SystemExit(f"ERROR: SHA256 mismatch for {name}: expected {package['sha256']}, got {digest}")
PY

imagebuilder_dir="$(extract_archive "$imagebuilder_url" "$work_dir/imagebuilder" "ImageBuilder")"
imagebuilder_config="$imagebuilder_dir/.config"
if grep -q '^CONFIG_TARGET_ROOTFS_PERSIST_VAR=y$' "$imagebuilder_config"; then
    echo "ERROR: AudioWRT requires volatile /var; persistent /var is unsupported." >&2
    exit 5
fi
mkdir -p "$imagebuilder_dir/packages"
cp -f "$local_apks"/*.apk "$imagebuilder_dir/packages/"

# Factory defaults are build policy, not a reason to compile package source.
# Fetch only the tiny package-owned settings files at the exact source commit
# recorded for the published APK when a selected feature needs them.
feed_stub="$work_dir/package-defaults-source"
mkdir -p "$feed_stub"
python3 - "$repository_metadata" "$packages_add_file" "$feed_stub" <<'PY'
import json, pathlib, sys, urllib.request
metadata = json.load(open(sys.argv[1], encoding="utf-8"))
selected = {line.strip() for line in open(sys.argv[2], encoding="utf-8") if line.strip() and not line.lstrip().startswith("#")}
root = pathlib.Path(sys.argv[3])
needs = {
    "audiowrt-airplay": "files/airplay.settings",
    "audiowrt-spotify": "files/spotify.settings",
    "audiowrt-mpd": "files/mpd.conf",
}
for package, relative in needs.items():
    if package not in selected:
        continue
    entry = metadata["packages"].get(package)
    if not entry:
        raise SystemExit(f"ERROR: published repository is missing {package} required for image defaults")
    url = f"https://raw.githubusercontent.com/demonccc/audiowrt-packages/{entry['source_commit']}/{entry['source_dir']}/{relative}"
    target = root / package / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "AudioWRT-builder"})
    with urllib.request.urlopen(request) as response:
        target.write_bytes(response.read())
PY

rm -rf "$image_defaults"
python3 "$repo_root/scripts/prepare-image-defaults.py" \
    "$packages_add_file" "$feed_stub" "$image_defaults" "$provisioning_ip"

package_args=()
while IFS= read -r package; do [[ -z "$package" ]] || package_args+=("$package"); done < "$packages_add_file"
while IFS= read -r package; do [[ -z "$package" ]] || package_args+=("-$package"); done < "$packages_remove_file"
package_string="${package_args[*]}"

if [[ "$squashfs_block_size" != default ]]; then
    if grep -q '^CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=' "$imagebuilder_config"; then
        sed -i "s/^CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=.*/CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=$squashfs_block_size/" "$imagebuilder_config"
    else
        printf 'CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=%s\n' "$squashfs_block_size" >> "$imagebuilder_config"
    fi
fi

make -C "$imagebuilder_dir" image \
    "FILES=$image_defaults" \
    "PROFILE=$platform" \
    "PACKAGES=$package_string" \
    "BIN_DIR=$output_dir"

python3 "$repo_root/scripts/image-size-report.py" \
    "$output_dir" "$output_dir/image-size-report.json" "$output_dir/image-size-report.txt"

cp "$resolved_profile" "$output_dir/audiowrt-profile.json"
cp "$artifacts_metadata" "$output_dir/openwrt-artifacts.json"
cp "$repository_metadata" "$output_dir/package-repository.json"
cp "$packages_add_file" "$output_dir/audiowrt-packages.add"
cp "$packages_remove_file" "$output_dir/audiowrt-packages.remove"
[[ -f "$imagebuilder_config" ]] && cp "$imagebuilder_config" "$output_dir/imagebuilder.config"

audiowrt_commit="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf unknown)"
cat > "$output_dir/BUILD_INFO" <<EOF
BUILD_MODE=published-packages-imagebuilder
AUDIOWRT_COMMIT=$audiowrt_commit
AUDIOWRT_PROFILE=$profile
AUDIOWRT_PROVISIONING_IP=$provisioning_ip
OPENWRT_VERSION=$openwrt_version
OPENWRT_RESOLVED_REF=$resolved_release
TARGET=$target
SUBTARGET=$subtarget
ARCHITECTURE=$architecture
IMAGEBUILDER_URL=$imagebuilder_url
AUDIOWRT_PACKAGES_CHANNEL=$channel
AUDIOWRT_PACKAGES_REPOSITORY=$repository_url
AUDIOWRT_PACKAGES_REVISION=$repository_revision
AUDIOWRT_PACKAGES_METADATA_SHA256=$repository_sha256
BUILDER_IMAGE=$builder_image
EOF

python3 - "$resolved_profile" "$repository_metadata" "$artifacts_metadata" "$output_dir/manifest.json" <<PY
import json, sys
profile = json.load(open(sys.argv[1], encoding="utf-8"))
repository = json.load(open(sys.argv[2], encoding="utf-8"))
artifacts = json.load(open(sys.argv[3], encoding="utf-8"))
manifest = {
    "build_mode": "published-packages-imagebuilder",
    "audiowrt_commit": "$audiowrt_commit",
    "audiowrt_profile": "$profile",
    "resolved_profile": profile,
    "openwrt_version": "$openwrt_version",
    "openwrt_resolved_ref": "$resolved_release",
    "openwrt_artifacts": artifacts,
    "package_repository_url": "$repository_url",
    "package_repository_channel": "$channel",
    "package_repository_revision": int("$repository_revision"),
    "package_repository_metadata_sha256": "$repository_sha256",
    "package_repository_last_release": repository.get("last_release_tag"),
    "package_repository_architecture": repository["architecture"],
}
with open(sys.argv[4], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

printf '\nAudioWRT firmware build complete.\nArtifacts: %s\n' "$output_dir"
cat "$output_dir/image-size-report.txt"
