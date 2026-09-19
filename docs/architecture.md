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

If OpenWrt already owns a canonical recipe for a package and AudioWRT really changes the compiled binary, AudioWRT does not pin a parallel upstream version or copy the OpenWrt patch set. The AudioWRT package derives from the canonical recipe exposed by the selected SDK/feed checkout and stores only the AudioWRT delta.

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
        +--> AudioWRT compiled-binary delta
               - feature removals/additions
               - packaging changes
               - optional 9xx AudioWRT source patches
        |
        v
AudioWRT derived APK for the selected release + architecture
```

This is the rule for **all** actual source-derived packages, including the constrained Bluetooth stack. The current source-derived set includes:

- `audiowrt-busybox` -> OpenWrt `busybox`;
- `audiowrt-dropbear` -> OpenWrt `dropbear`;
- `audiowrt-wpad` -> OpenWrt `hostapd` source, linked as one multicall binary exposing both `hostapd` and `wpa_supplicant`;
- `audiowrt-umdns` -> OpenWrt `umdns` when that package is explicitly selected as a custom source build;
- `audiowrt-minimal-alsa` -> packages feed `alsa-lib`;
- `audiowrt-sbc` -> packages feed `sbc`;
- `audiowrt-bluez` -> packages feed `bluez`.

The implementation lives in `demonccc/audiowrt-packages` through `include/audiowrt-openwrt-derived.mk` and `scripts/prepare-openwrt-derived.py`. The helper inherits the canonical recipe preamble, files and patch set from the exact selected OpenWrt context. AudioWRT-owned source patches use the `9xx-*` namespace so they cannot silently replace an OpenWrt-owned patch.

Core OpenWrt recipes are resolved from the `package/` tree already present in the selected OpenWrt SDK/source checkout. The helper must never run `scripts/feeds update base` to create a second core source tree. Duplicating that tree produces duplicate Kconfig symbols and can accidentally broaden a selective build.

A release-family-specific compatibility delta may exist under `releases/<major.minor>/` when OpenWrt changes a configure option or source interface between releases. Those fragments contain only the AudioWRT delta; they do not duplicate OpenWrt version/hash/patch metadata.

Therefore a 24.10 build and a 25.12 build may compile different upstream versions and different OpenWrt patch sets while using the same AudioWRT package name and feature intent.

### 2. Exact-release selectors, runtime profiles and prebuilt replacements

A package must **not** become a source build merely because AudioWRT changes its runtime configuration. If the compiled upstream binary is unchanged, AudioWRT reuses the exact official release binary.

Current examples:

- both minimal and standard audio runtimes use the exact official OpenWrt `mpd-mini` and `upmpdcli` binaries rather than rebuilding them;
- `audiowrt-minimal-upmpdcli` is a file-only runtime profile over those release binaries and is built with `NO_DEPS=1`;
- minimal currently uses the official `umdns` package because `.local`/mDNS does not justify rebuilding the daemon;
- `audiowrt-kmod-bluetooth`, `kmod-audiowrt-sound-core` and `kmod-audiowrt-usb-audio` repackage modules from the exact release/target instead of rebuilding the kernel.

The kmod strategy preserves the selected kernel ABI, architecture and OpenWrt target patches automatically. A package for `ath79/generic` can never reuse modules from another target or OpenWrt release.

### 3. AudioWRT-owned source packages

If there is no canonical package in the supported OpenWrt `base` or `packages` feed, AudioWRT owns the recipe. Examples currently include `bluez-alsa` and `librespot`.

These packages may pin their upstream source because there is no OpenWrt recipe to inherit, but they still compile using the SDK/toolchain/target selected by the profile. If OpenWrt later gains a canonical recipe, the package should be migrated to the derived model.

## Network audio renderer

AudioWRT exposes UPnP AV/DLNA as its network-facing renderer protocol. MPD is an internal playback backend, not the public discovery/control interface.

```text
UPnP/DLNA controller
        |
        v
     upmpdcli
        |
  localhost:6600
        |
        v
       MPD
        |
       ALSA
      /    \
 USB Audio  BlueALSA
```

The constrained runtime uses the exact OpenWrt `upmpdcli` and `mpd-mini` release binaries. `audiowrt-minimal-upmpdcli` only applies runtime policy: OpenHome is disabled, MPD stays on loopback, and the renderer advertises the constrained FLAC + MP3 sink profile. Standard builds use the same official OpenWrt binaries without the constrained renderer profile.

`audiowrt-mpd` is a small shared runtime configuration layer. It binds MPD to `127.0.0.1:6600`, so UPnP/DLNA remains the externally visible renderer interface while the selected MPD provider stays internal.

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
8. Register only selected AudioWRT source directories in the SDK package tree
9. Resolve selected AudioWRT package closure
10. Split targets into:
    - package-only wrappers/selectors/config/LuCI -> NO_DEPS=1
    - real compiled-source packages -> explicit source dependency path
11. For OpenWrt-derived source packages:
    - resolve core recipes from the SDK/source `package/` tree
    - inherit canonical recipe preamble
    - inherit canonical files
    - inherit all canonical OpenWrt patches
    - apply only the AudioWRT delta
12. For binary-reuse/runtime-profile packages:
    - keep the official release binary as runtime dependency
    - build only the AudioWRT policy/config layer with NO_DEPS=1
13. For prebuilt kmod replacements:
    - download exact release/target APKs
    - verify OpenWrt checksums
    - extract only the required modules
14. Build only the required local AudioWRT APKs with the selected SDK/toolchain
15. Prepare the official ImageBuilder for the same release/target
16. Inject local AudioWRT APKs and resolved package add/remove policy
17. Build firmware and write provenance metadata
```

## Official feeds

The official SDK's `feeds.conf.default` is authoritative. AudioWRT never replaces it with a hand-written release branch.

For an official release SDK, its feed entries identify the matching OpenWrt source/feed revisions. `feeds.buildinfo` is downloaded separately and retained as provenance.

The `packages` feed is updated because AudioWRT uses package recipes/build helpers from it. Core recipes used by source-derived AudioWRT packages are taken from the core package tree already present in the selected build context; the package derivation helper does not materialize a second `base` package tree.

This is what makes the package model portable across 24.10, 25.12, snapshots and future releases: **the profile selects OpenWrt; OpenWrt selects the package versions and patches; AudioWRT supplies only its delta.**

## Package compilation scope

`config/build/package-build-targets` maps AudioWRT binary packages to SDK make targets. `config/build/source-build-packages` is a strict opt-in list containing only packages that genuinely compile/link a different binary.

Package-only wrappers remain behind `NO_DEPS=1`, so unchanged runtime dependencies such as LuCI, uhttpd, umdns, `mpd-mini` and `upmpdcli` remain official binaries. TLS is also kept fully official: both minimal and standard images use OpenWrt's `libmbedtls21`; AudioWRT does not ship a replacement mbedTLS runtime. `audiowrt-wpad` is a special constrained source-derived package: it compiles upstream hostap code behind the same `NO_DEPS=1` boundary while the builder stages only the exact-release development interfaces it needs.

A package may enter `source-build-packages` only if AudioWRT has a real compiled-source delta. Adding it means explicitly accepting compilation of the build/link dependency closure required to produce that binary. A wrapper, selector or runtime-profile package must never be added simply because it references an upstream project.

In particular, `audiowrt-minimal-upmpdcli` is configuration-only and must stay out of `source-build-packages`. Rebuilding it would recursively compile `libupnpp`, MPD-related libraries and their transitive dependencies even though AudioWRT does not change the upstream executable. The constrained firmware therefore installs the official `mpd-mini` and `upmpdcli` release binaries through ImageBuilder and builds only the small AudioWRT runtime profile with `NO_DEPS=1`.

## Firmware composition

Package composition is resolved from reusable package groups:

```text
common
  + minimal or standard
  + capability group (USB audio / Bluetooth / combined)
  + profile-specific overrides
```

`common` contains implementation-neutral AudioWRT product policy. `minimal` selects constrained providers where AudioWRT has a real minimal implementation; otherwise it reuses the exact official release package. `standard` selects the normal OpenWrt providers. Capability groups describe the required audio hardware/runtime path and inherit one of those runtime layers.

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
