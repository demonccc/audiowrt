# AudioWRT Architecture

## Build contract

AudioWRT firmware is anchored to one exact final OpenWrt release tag. Builds from moving branches, aliases or snapshots are intentionally unsupported.

```text
OPENWRT_RELEASE=25.12.5
        |
        v
v25.12.5
```

`stable`, `openwrt-X.Y`, `main`, snapshots and release candidates are rejected. The default release is explicitly pinned by AudioWRT and must be updated deliberately when a newer OpenWrt release is adopted.

The exact release establishes a compatibility contract across:

- OpenWrt source metadata;
- target/subtarget/device profile;
- official SDK;
- official ImageBuilder;
- official binary repositories;
- feed commit provenance from `feeds.buildinfo`.

## Relationship to openwrt-builder

The build model copies the release discipline of the `release-patched` method in `demonccc/openwrt-builder`.

`release-patched` must sometimes rebuild target/kernel source and generate a custom ImageBuilder. AudioWRT does not patch OpenWrt target or kernel source, so it uses a narrower variant:

```text
exact release source metadata
       +
official SDK -> AudioWRT APK layer
       +
official ImageBuilder -> final firmware
```

This retains official release binaries for unchanged packages and avoids a complete OpenWrt source build.

The recent `openwrt-builder` release-patched fixes keep SDK/kernel/host-tool state coherent when a custom kernel or ImageBuilder is generated. AudioWRT does not generate an ImageBuilder at all: it uses the official ImageBuilder directly, so that class of problem is structurally avoided.

## Docker responsibility

AudioWRT does not own a Docker build environment.

```text
demonccc/openwrt-builder
        |
        +--> publishes demonccc/openwrt-builder:latest

AudioWRT
        |
        +--> docker pull demonccc/openwrt-builder:latest
        +--> mount current checkout at /workspace
        +--> run scripts/build.sh inside the image
```

There is no Dockerfile and no local Docker-build fallback in AudioWRT. Build-environment changes belong in `openwrt-builder`.

The builder image is part of the AudioWRT build contract and is deliberately fixed to `demonccc/openwrt-builder:latest`. It is not a Makefile parameter, environment override or GitHub Actions input.

## Build flow

```text
1. Validate exact release tag
2. Clone exact OpenWrt tag for authoritative device metadata
3. Resolve PLATFORM -> target/subtarget
4. Validate USB host support
5. Resolve official SDK + ImageBuilder URLs
6. Download official feeds.buildinfo as provenance
7. Prepare official SDK
   - preserve SDK feeds.conf.default
   - copy AudioWRT distribution-only packages
   - append audiowrt-packages feed
   - update only packages helper feed + audiowrt feed for core builds
   - register AudioWRT feed sources directly, without recursive runtime-dependency install
8. Resolve selected AudioWRT package closure
9. Split AudioWRT targets into:
   - package-only targets -> NO_DEPS=1
   - genuine source targets -> explicit build dependency path
10. Compile/package AudioWRT APKs
11. Collect local AudioWRT APKs
12. Prepare official ImageBuilder
13. Copy local AudioWRT APKs into ImageBuilder packages/
14. make image with:
    - OpenWrt device defaults
    - AudioWRT core packages
    - optional FEATURES
    - generic router package exclusions
    - AudioWRT FILES overlay
15. Write firmware + BUILD_INFO + manifest
```

## Official feeds

AudioWRT keeps the `feeds.conf.default` generated into the official SDK for the exact release. It does not replace that file with `feeds.buildinfo`.

The target release's `feeds.buildinfo` is downloaded and preserved separately as provenance. The reusable `audiowrt-packages` feed is separately recorded by its actual Git commit in the build manifest.

For core/package-only builds, AudioWRT updates only the `packages` feed (needed for shared package build helpers such as Rust definitions) and the `audiowrt` feed. It does not install OpenWrt runtime dependencies into the SDK source package tree.

## Package compilation scope

`config/package-build-targets` maps AudioWRT-owned binary packages to SDK make targets. `config/source-build-packages` identifies the small subset that genuinely compiles or links upstream source code.

The default behavior is package-only:

```text
AudioWRT wrapper/config/LuCI package
        |
        +--> explicit SDK target
        +--> NO_DEPS=1
        |
        v
AudioWRT APK
```

Runtime dependencies such as `hostapd`, `dnsmasq`, `uhttpd`, `uci`, `ubus`, kernel packages and OpenWrt libraries are not rebuilt for those targets. They remain dependency metadata in the APK and are resolved by the official ImageBuilder from the exact release repositories.

Only genuine AudioWRT source packages, currently `librespot` and `bluez-alsa`, are allowed to traverse SDK build dependencies. Those packages need development headers/libraries/tooling to produce their AudioWRT-owned binary, so the build resolves their external source dependency roots only when the corresponding feature is selected.

A core-only build must therefore compile/package only the AudioWRT core layer and must not enter hostapd, dnsmasq, kernel or other unrelated OpenWrt source builds.

## Firmware composition

```text
OpenWrt device defaults
+ config/packages.add
+ selected feature packages
- config/packages.remove
+ local AudioWRT APK repository
+ files/ overlay
```

The official ImageBuilder remains responsible for dependency solving, device image layout and maximum image-size enforcement.

## Hardware ownership

AudioWRT does not maintain target/platform YAML or board metadata. OpenWrt remains authoritative for:

- target and subtarget;
- device definitions;
- kernel configuration;
- Wi-Fi firmware;
- Ethernet/switch drivers;
- USB host-controller packages;
- device image layout.

The TP-Link TL-WDR4300 v1 (`tplink_tl-wdr4300-v1`) is only the initial reference target.

## Reproducibility metadata

Every build records:

- canonical builder Docker image;
- AudioWRT commit;
- AudioWRT packages repository/ref/commit;
- exact OpenWrt release tag and commit;
- target/subtarget/profile;
- official SDK URL;
- official ImageBuilder URL;
- official `feeds.buildinfo` provenance;
- selected features;
- AudioWRT package-only/source-build split;
- external source-build dependency roots when applicable;
- locally built APK count;
- firmware image-size report.

For reproducible package content, pin `AUDIOWRT_PACKAGES_REF=<commit>` together with the exact OpenWrt release. The Docker environment is not caller-selectable; AudioWRT always uses its canonical `demonccc/openwrt-builder:latest` image.
