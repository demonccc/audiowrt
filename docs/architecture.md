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
- feed commit pins from `feeds.buildinfo`.

## Relationship to openwrt-builder

The build model copies the release discipline of the `release-patched` method in `demonccc/openwrt-builder`.

`release-patched` must sometimes rebuild target/kernel source and generate a custom ImageBuilder. AudioWRT does not patch OpenWrt target or kernel source, so it uses a narrower variant:

```text
exact release source metadata
       +
official SDK -> AudioWRT APKs
       +
official ImageBuilder -> final firmware
```

This retains official release binaries for unchanged packages and avoids a complete OpenWrt source build.

The recent `openwrt-builder` release-patched fix keeps SDK host tools out of generated ImageBuilders because those host tools would otherwise be bundled twice. AudioWRT does not generate an ImageBuilder at all: it uses the official ImageBuilder directly, so that class of problem is structurally avoided.

## Docker responsibility

AudioWRT does not own a Docker build environment.

```text
demonccc/openwrt-builder
        |
        +--> publishes demonccc/openwrt-builder:<tag>

AudioWRT
        |
        +--> docker pull configured image
        +--> mount current checkout at /workspace
        +--> run scripts/build.sh inside the image
```

There is no Dockerfile and no local Docker-build fallback in AudioWRT. Build-environment changes belong in `openwrt-builder`.

## Build flow

```text
1. Validate exact release tag
2. Clone exact OpenWrt tag
3. Generate target metadata
4. Resolve PLATFORM -> target/subtarget
5. Validate USB host support
6. Resolve official SDK + ImageBuilder URLs
7. Download official feeds.buildinfo
8. Prepare SDK
   - keep SDK target configuration
   - pin official feeds to release commits
   - copy AudioWRT distribution-only packages
   - add audiowrt-packages feed
   - select AudioWRT-owned packages
9. Compile only selected AudioWRT-owned SDK targets
10. Collect AudioWRT APKs
11. Prepare official ImageBuilder
12. Copy local AudioWRT APKs into ImageBuilder packages/
13. make image with:
    - OpenWrt device defaults
    - AudioWRT core packages
    - optional FEATURES
    - generic router package exclusions
    - AudioWRT FILES overlay
14. Write firmware + BUILD_INFO + manifest
```

## Official feeds

The SDK's moving feed definitions are not used for exact-release builds. AudioWRT replaces them with the target release's official `feeds.buildinfo`.

For example, an official target release records feed URLs together with exact commit hashes. That means a later rebuild of the same OpenWrt release does not accidentally compile AudioWRT against a newer `packages` or `luci` branch.

The reusable `audiowrt-packages` feed is separately recorded by its actual Git commit in the build manifest.

## Package compilation scope

`config/package-build-targets` maps AudioWRT-owned binary packages to SDK make targets.

After `make defconfig`, only mapped packages selected as `y` or `m` are compiled. This allows package dependencies to select additional AudioWRT-owned packages such as `librespot` or `bluez-alsa` without compiling unrelated feed content.

Official OpenWrt dependencies may compile inside the SDK when needed to provide build-time headers/libraries, but their APKs are not injected into the final ImageBuilder. Final unchanged packages resolve from the official release repositories.

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

- builder Docker image;
- AudioWRT commit;
- AudioWRT packages repository/ref/commit;
- exact OpenWrt release tag and commit;
- target/subtarget/profile;
- official SDK URL;
- official ImageBuilder URL;
- exact official `feeds.buildinfo`;
- selected features;
- locally built APK count;
- firmware image-size report.

For the strongest reproducibility, use an immutable `BUILDER_IMAGE=...:sha-<commit>` and an immutable `AUDIOWRT_PACKAGES_REF=<commit>` together with the exact OpenWrt release.
