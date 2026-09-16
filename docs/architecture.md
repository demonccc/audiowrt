# AudioWRT Architecture

## Build contract

Each AudioWRT profile declares its OpenWrt source/version and target mapping. Release profiles are anchored to an exact final tag; explicitly named snapshot profiles are moving, experimental builds.

```text
tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5
        -> release tag v25.12.5
        -> ath79/generic
        -> official SDK + ImageBuilder for that exact release/target
```

`stable`, implicit branch aliases, release candidates and caller-provided version overrides are rejected for release profiles. Moving builds must be explicitly named `-snapshot`.

The exact release establishes one compatibility context across:

- OpenWrt source metadata;
- target/subtarget/device profile;
- official SDK and toolchain;
- official ImageBuilder;
- official binary repositories;
- the SDK-pinned `base` and `packages` feed revisions;
- kernel ABI and target-specific kmods.

## Package provenance rule

AudioWRT packages fall into three provenance classes.

### 1. OpenWrt-derived source packages

If OpenWrt already owns a canonical recipe for a package, AudioWRT does not pin a parallel upstream version or copy the OpenWrt patch set. The AudioWRT package derives from the canonical recipe exposed by the selected SDK/feed checkout and stores only the AudioWRT delta.

```text
selected OpenWrt release/SDK
        |
        +--> exact canonical recipe
        |      - source version/revision
        |      - source URL/hash
        |      - OpenWrt build flags/hardening
        |      - canonical files
        |      - complete OpenWrt patch set
        |
        +--> AudioWRT delta
               - feature removals/additions
               - packaging changes
               - optional 9xx AudioWRT source patches
        |
        v
AudioWRT derived APK for the selected release + architecture
```

This is the rule for **all** derived packages, including the Bluetooth stack. The current derived set is:

- `audiowrt-busybox` -> `base/utils/busybox`;
- `audiowrt-minimal-mbedtls` -> `base/libs/mbedtls`;
- `audiowrt-dropbear` -> `base/network/services/dropbear`;
- `audiowrt-umdns` -> `base/network/services/umdns`;
- `audiowrt-minimal-alsa` -> `packages/libs/alsa-lib`;
- `audiowrt-minidlna` -> `packages/multimedia/minidlna`;
- `audiowrt-sbc` -> `packages/libs/sbc`;
- `audiowrt-bluez` -> `packages/utils/bluez`.

The implementation lives in `demonccc/audiowrt-packages` through `include/audiowrt-openwrt-derived.mk` and `scripts/prepare-openwrt-derived.py`. The helper inherits the canonical recipe preamble, files and patch set from the exact selected OpenWrt context. AudioWRT-owned source patches use the `9xx-*` namespace so they cannot silently replace an OpenWrt-owned patch.

A release-family-specific compatibility delta may exist under `releases/<major.minor>/` when OpenWrt changes a configure option or source interface between releases. Those fragments contain only the AudioWRT delta; they do not duplicate OpenWrt version/hash/patch metadata.

Therefore a 24.10 build and a 25.12 build may compile different upstream versions and different OpenWrt patch sets while using the same AudioWRT package name and feature intent.

### 2. Exact-release selectors and prebuilt kmod replacements

Some AudioWRT packages do not rebuild an OpenWrt userspace source tree:

- `audiowrt-wpa-supplicant` selects the exact `wpa-supplicant-mbedtls` package from the selected release instead of carrying a hostapd/wpa source fork;
- `audiowrt-kmod-bluetooth`, `kmod-audiowrt-sound-core` and `kmod-audiowrt-usb-audio` repackage modules from the exact release/target instead of rebuilding the kernel.

The kmod strategy preserves the selected kernel ABI, architecture and OpenWrt target patches automatically. A package for `ath79/generic` can never reuse modules from another target or OpenWrt release.

### 3. AudioWRT-owned source packages

If there is no canonical package in the supported OpenWrt `base` or `packages` feed, AudioWRT owns the recipe. Examples currently include `bluez-alsa` and `librespot`.

These packages may pin their upstream source because there is no OpenWrt recipe to inherit, but they still compile using the SDK/toolchain/target selected by the profile. If OpenWrt later gains a canonical recipe, the package should be migrated to the derived model.

## Relationship to openwrt-builder

The build model follows the release discipline of `release-patched` in `demonccc/openwrt-builder`, but AudioWRT does not patch OpenWrt target/kernel source or generate a custom ImageBuilder.

```text
exact release metadata
       +
official SDK -> AudioWRT APK layer
       +
official ImageBuilder -> final firmware
```

Unchanged OpenWrt packages remain official release binaries.

## Docker responsibility

AudioWRT does not own a Docker build environment. It always uses:

```text
demonccc/openwrt-builder:latest
```

The image is the build environment only; AudioWRT scripts come from the mounted checkout. There is no local Dockerfile fallback.

## Build flow

```text
1. Resolve and validate the AudioWRT profile
2. Resolve the exact OpenWrt release tag or explicit snapshot
3. Resolve device -> target/subtarget from authoritative OpenWrt metadata
4. Resolve official SDK + ImageBuilder URLs for that target
5. Extract the official SDK and preserve its feeds.conf.default
6. Append only the AudioWRT feed
7. Update the SDK-pinned packages feed + AudioWRT feed
8. Derived package helper resolves the SDK-pinned base feed when a base recipe is needed
9. Register only selected AudioWRT source directories in the SDK package tree
10. Resolve selected AudioWRT package closure
11. Split targets into:
    - package-only wrappers/config/LuCI -> NO_DEPS=1
    - source packages -> explicit source dependency path
12. For OpenWrt-derived source packages:
    - inherit canonical recipe preamble
    - inherit canonical files
    - inherit all canonical OpenWrt patches
    - apply only the AudioWRT delta
13. For prebuilt kmod replacements:
    - download exact release/target APKs
    - verify OpenWrt checksums
    - extract only the required modules
14. Build local AudioWRT APKs with the selected SDK/toolchain
15. Prepare the official ImageBuilder for the same release/target
16. Inject local AudioWRT APKs and resolved package add/remove policy
17. Build firmware and write provenance metadata
```

## Official feeds

The official SDK's `feeds.conf.default` is authoritative. AudioWRT never replaces it with a hand-written release branch.

For an official release SDK, its feed entries identify the matching OpenWrt source/feed revisions. `feeds.buildinfo` is downloaded separately and retained as provenance.

The `packages` feed is updated because AudioWRT uses package recipes/build helpers from it. The `base` feed is resolved when a derived package needs a canonical core recipe. Neither feed is replaced with an AudioWRT-selected branch or version.

This is what makes the package model portable across 24.10, 25.12, snapshots and future releases: **the profile selects OpenWrt; OpenWrt selects the package versions and patches; AudioWRT supplies only its delta.**

## Package compilation scope

`config/build/package-build-targets` maps AudioWRT binary packages to SDK make targets. `config/build/source-build-packages` identifies packages that genuinely compile/link source.

Package-only wrappers remain behind `NO_DEPS=1`, so runtime dependencies such as LuCI, uhttpd, ubus and unrelated OpenWrt packages remain official binaries.

Source builds are allowed only for selected AudioWRT roots and their explicit build dependencies. This includes OpenWrt-derived minimal replacements such as BusyBox, ALSA, mbedTLS, BlueZ/SBC, Dropbear, MiniDLNA and umdns, plus AudioWRT-owned upstream packages such as BlueALSA/librespot when selected.

## Firmware composition

Package composition is resolved from reusable package groups:

```text
common
  + minimal or standard
  + capability group (USB audio / Bluetooth / combined)
  + profile-specific overrides
```

`common` contains implementation-neutral AudioWRT product policy. `minimal` selects constrained providers; `standard` selects the normal OpenWrt providers. Capability groups describe the required audio hardware/runtime path and inherit one of those runtime layers.

The official ImageBuilder remains responsible for dependency solving, device image layout and image-size enforcement.

## Hardware ownership

OpenWrt remains authoritative for:

- target/subtarget and device definitions;
- kernel configuration and ABI;
- Wi-Fi/Ethernet/USB drivers and firmware;
- architecture/toolchain;
- target-specific patches;
- device image layout.

AudioWRT does not create architecture-specific package forks. A derived userspace package compiles with the SDK selected by the profile; a kmod replacement is assembled only from modules belonging to that exact release/target.

## Reproducibility metadata

Every build records the selected AudioWRT profile, exact OpenWrt source/release, target/subtarget, official SDK/ImageBuilder URLs, official feed provenance, AudioWRT package repository commit, package build plan and generated APKs.

For reproducible package content, pin `AUDIOWRT_PACKAGES_REF=<commit>` together with an exact release profile. Snapshot profiles are intentionally moving builds.
