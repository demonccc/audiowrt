# AudioWRT

AudioWRT is an audio-focused OpenWrt distribution that turns compatible OpenWrt devices into lightweight network audio appliances.

AudioWRT does not maintain a fork of the OpenWrt source tree. Every firmware build is anchored to an **exact final OpenWrt release**, uses the official SDK and ImageBuilder for that same release/target, compiles only AudioWRT-owned packages, and assembles the final image from official release binaries plus the AudioWRT layer.

## Exact-release policy

AudioWRT intentionally does not build from moving OpenWrt branches or snapshots.

Accepted:

```text
stable     -> resolves the latest final OpenWrt tag
25.12.5    -> normalized to v25.12.5
v25.12.5   -> exact tag
```

Rejected:

```text
openwrt-25.12
main
master
snapshot
v25.12.5-rc1
```

This makes the OpenWrt ABI, SDK, ImageBuilder and binary repositories a single release contract.

## Build model

The build follows the same release-binary principle used by `release-patched` in [`demonccc/openwrt-builder`](https://github.com/demonccc/openwrt-builder), but AudioWRT does not patch OpenWrt kernel/target sources.

```text
Exact OpenWrt release tag (for example v25.12.5)
                |
                v
Clean source checkout for device metadata only
                |
                +--> resolve PLATFORM -> target/subtarget
                +--> validate USB host support
                |
                v
Official SDK for the exact release/target
                |
                +--> official feeds pinned from feeds.buildinfo
                +--> AudioWRT distribution packages
                +--> audiowrt-packages feed
                |
                v
Compile only AudioWRT-owned APKs
                |
                v
Official ImageBuilder for the same exact release/target
                |
                +--> official release repositories
                +--> locally built AudioWRT APKs
                +--> AudioWRT package include/exclude policy
                +--> AudioWRT filesystem overlay
                |
                v
AudioWRT firmware
```

Unchanged OpenWrt packages are never rebuilt just because AudioWRT is being built. They come from the official repositories referenced by the exact release ImageBuilder.

The SDK feed definitions are replaced with the release target's official `feeds.buildinfo`, which pins packages, LuCI, routing and other feeds to the exact commits used for that OpenWrt release.

## Docker build environment

AudioWRT has **no Dockerfile** and does not publish a separate builder image.

Both local and GitHub-hosted builds use the existing image from `demonccc/openwrt-builder`:

```text
demonccc/openwrt-builder:latest
```

Run:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5
```

`make build` pulls the configured image and executes the AudioWRT build inside it. If the image cannot be pulled, the build fails; AudioWRT never falls back to building a Docker image locally.

A different published/pinned builder image can be selected:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5 \
  BUILDER_IMAGE=demonccc/openwrt-builder:sha-<commit>
```

The selected builder image is recorded in `BUILD_INFO` and `manifest.json`.

## Why the SDK + official ImageBuilder split

`release-patched` in `openwrt-builder` may generate a custom ImageBuilder because it can change target/kernel source. AudioWRT does not need that step.

AudioWRT uses the official SDK only to compile its own packages and then injects those APKs into the official ImageBuilder. This also means SDK host tools are not copied into a generated ImageBuilder, avoiding the double-bundled host-tool class fixed in the current `openwrt-builder` release-patched implementation.

## Core versus optional audio engines

The default firmware is the AudioWRT core:

- AudioWRT appliance identity;
- Ethernet DHCP-client behavior;
- temporary Wi-Fi provisioning AP and STA onboarding;
- guided external storage support;
- USB Audio Class and ALSA output management;
- minimal LuCI (`luci-base` + AudioWRT applications);
- AudioWRT extension management.

MPD, AirPlay, Spotify Connect and Bluetooth audio remain optional build-time features:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5 \
  FEATURES="mpd spotify"
```

Available feature IDs:

```text
mpd
airplay
spotify
bluetooth
```

OpenWrt ImageBuilder enforces the selected device's image-size limit. AudioWRT does not silently drop requested features.

## Reference device

The initial reference/test device is the TP-Link TL-WDR4300 v1:

```text
PLATFORM=tplink_tl-wdr4300-v1
```

Example core build:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5
```

The WDR4300 is a reference target only. AudioWRT does not maintain its own hardware database; device-specific drivers, firmware and base package choices remain OpenWrt responsibilities.

## USB capability gate

USB host support is mandatory for the initial AudioWRT architecture.

The build checks the selected device profile from the exact OpenWrt release source **before** AudioWRT USB packages are introduced:

```text
USB confirmed -> continue
USB missing   -> fail
USB unknown   -> fail
```

This prevents `kmod-usb-audio` from creating a false positive on devices whose OpenWrt profile does not prove USB host support.

## Package ownership

Distribution-only behavior lives in this repository under `package/`:

```text
package/
├── audiowrt-core
├── audiowrt-provisioning
├── audiowrt-storage
└── luci-app-audiowrt-core
```

Reusable audio functionality comes from [`demonccc/audiowrt-packages`](https://github.com/demonccc/audiowrt-packages):

```text
audiowrt-audio
audiowrt-usb-audio
audiowrt-extensions
audiowrt-mpd
audiowrt-airplay
audiowrt-spotify
audiowrt-bluetooth
librespot
bluez-alsa
luci-app-audiowrt
```

Installing the reusable feed on a normal OpenWrt system does not change its LAN, DHCP, firewall, Wi-Fi provisioning or storage role.

## Build inputs

```text
PLATFORM                 required OpenWrt device profile
OPENWRT_RELEASE          stable or exact X.Y.Z / vX.Y.Z release
AUDIOWRT_PACKAGES_REF    reusable package-feed branch/tag/commit (default main)
FEATURES                 optional music engines
JOBS                     package build parallelism
VERBOSITY                normal, verbose or debug
BUILDER_IMAGE             existing openwrt-builder image
```

For example:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5 \
  AUDIOWRT_PACKAGES_REF=main \
  FEATURES="mpd airplay" \
  JOBS=8 \
  VERBOSITY=verbose
```

## Build outputs

Firmware is written under:

```text
output/<platform>/v<release>/
```

The output also records:

- `BUILD_INFO`;
- `manifest.json`;
- exact OpenWrt commit;
- exact SDK and ImageBuilder URLs;
- exact official feed commits used by the release;
- actual `audiowrt-packages` commit;
- selected features;
- resolved platform metadata;
- SDK/ImageBuilder configuration;
- locally compiled AudioWRT APKs;
- image-size report.

## GitHub Actions policy

GitHub Actions are manual-only (`workflow_dispatch`). Pushes and pull requests do not start hosted runners automatically.

The manual workflow uses the same `make build` command as a local build and the same existing `openwrt-builder` Docker image. There is no AudioWRT Docker-image workflow.

## License

AudioWRT-specific GPL code in this repository is licensed under GPL-2.0-only unless stated otherwise. Software pulled from OpenWrt and external package feeds keeps its original license.
