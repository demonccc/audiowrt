# AudioWRT

AudioWRT is an audio-focused OpenWrt distribution that turns compatible OpenWrt devices into lightweight network audio appliances.

AudioWRT does not maintain a fork of the OpenWrt source tree. Every firmware build is anchored to an **exact final OpenWrt release**, uses the official SDK and ImageBuilder for that same release/target, builds the AudioWRT layer, and assembles the final image from official release binaries plus locally produced AudioWRT APKs.

## Exact-release policy

AudioWRT intentionally does not build from moving OpenWrt branches, snapshots, aliases or release candidates.

Accepted:

```text
25.12.5    -> normalized to v25.12.5
v25.12.5   -> exact tag
```

Rejected:

```text
stable
openwrt-25.12
main
master
snapshot
v25.12.5-rc1
```

The default is explicitly pinned to:

```text
OPENWRT_RELEASE=25.12.5
```

Moving to a newer OpenWrt version is therefore a deliberate AudioWRT change instead of an implicit consequence of an upstream branch or alias moving.

## Build model

AudioWRT follows the release-binary principle used by `release-patched` in [`demonccc/openwrt-builder`](https://github.com/demonccc/openwrt-builder), but AudioWRT does not patch OpenWrt kernel or target sources and does not generate a custom ImageBuilder.

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
                +--> preserve official feeds.conf.default
                +--> update only package helpers + audiowrt feed for core builds
                +--> register AudioWRT package sources without recursively installing runtime deps
                |
                v
Package-only AudioWRT APKs
                |
                +--> explicit AudioWRT targets
                +--> NO_DEPS=1
                +--> no hostapd/dnsmasq/uhttpd/kernel rebuilds
                |
                +--> optional genuine AudioWRT source packages
                     may stage only the build dependencies they actually need
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

For the core image and wrapper-style AudioWRT packages, unchanged OpenWrt packages are **not rebuilt** just because they appear in `DEPENDS`. They remain runtime dependencies and are resolved by the official ImageBuilder from the exact release repositories.

Most AudioWRT packages only install scripts, configuration, LuCI files or service wrappers. Those packages are built with OpenWrt's `NO_DEPS=1` boundary. This prevents runtime dependencies such as `hostapd`, `dnsmasq`, `uhttpd`, `uci`, `ubus`, kernel packages and OpenWrt libraries from becoming SDK compile targets.

A very small set of AudioWRT-owned packages genuinely compiles upstream source (`librespot` and `bluez-alsa`). They are classified separately in `config/source-build-packages`. Only when such a feature is selected may the SDK stage and build the external development dependencies required to compile/link that AudioWRT-owned binary.

The SDK's generated `feeds.conf.default` remains authoritative. The release `feeds.buildinfo` is retained separately as provenance; it is not used as a replacement feed configuration.

## Docker build environment

AudioWRT has **no Dockerfile** and does not publish a separate builder image.

Both local and GitHub-hosted builds always use the canonical image from `demonccc/openwrt-builder`:

```text
demonccc/openwrt-builder:latest
```

This image is part of the AudioWRT build contract and is intentionally **not configurable** from the Makefile, environment or GitHub Actions inputs. Changes to the build environment belong in `demonccc/openwrt-builder`, where its Dockerfile and image publication are maintained.

Run:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5
```

`make build` pulls the canonical image and executes the AudioWRT build inside it. If the image cannot be pulled, the build fails; AudioWRT never falls back to building or substituting a Docker image locally.

The Docker image is the build environment only. AudioWRT scripts come from the mounted AudioWRT checkout, so script-only changes do not require rebuilding the `openwrt-builder` image.

The canonical builder image is recorded in `BUILD_INFO` and `manifest.json`.

## Build diagnostics

AudioWRT mirrors the current `openwrt-builder` verbosity model:

```text
VERBOSITY=normal   -> default OpenWrt output
VERBOSITY=verbose  -> V=s
VERBOSITY=debug    -> V=sc
```

For difficult local failures, use one job and save the complete host-side output:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5 \
  JOBS=1 \
  VERBOSITY=debug \
  LOG_FILE=logs/wdr4300.log
```

`LOG_FILE` is local-only. It captures the Docker pull and the complete container output while still showing the same stream in the terminal. The path must stay outside `.work/` and `output/` because those directories are recreated during builds.

The builder's persistent-download-cache pattern also applies to AudioWRT. Local builds can opt in with:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5 \
  CACHE_DIR=.cache/audiowrt
```

When enabled, AudioWRT reuses the exact-release SDK archive, the exact-release ImageBuilder archive, and OpenWrt package/source downloads. Compilation state is still recreated on every build. `.cache/` is ignored by Git and `make clean` does not remove it.

For repeated troubleshooting, combine both features:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5 \
  CACHE_DIR=.cache/audiowrt \
  JOBS=1 \
  VERBOSITY=debug \
  LOG_FILE=logs/wdr4300.log
```

GitHub Actions does not expose either a log-file or cache input. Hosted jobs remain clean and ephemeral, and the Actions job already retains its complete console log. Firmware artifacts are uploaded only after a successful build.

The latest `openwrt-builder` stabilization changes how `release-patched` handles SDK host tools and generated custom ImageBuilders. AudioWRT does not need equivalent host-tool replacement logic because it uses the official SDK to build its package layer and the official ImageBuilder to assemble the firmware directly.

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

OpenWrt ImageBuilder enforces the selected device's image-size limit. AudioWRT does not silently drop requested features. On constrained devices, larger services can instead be installed later through AudioWRT Extensions and optional USB extension storage.

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
OPENWRT_RELEASE          exact X.Y.Z / vX.Y.Z release (default 25.12.5)
AUDIOWRT_PACKAGES_REF    reusable package-feed branch/tag/commit (default main)
FEATURES                 optional music engines
JOBS                     package build parallelism
VERBOSITY                normal, verbose or debug
LOG_FILE                 optional local-only diagnostic log path
CACHE_DIR                optional local-only persistent download cache
```

The Docker builder image is intentionally not an input.

For example:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5 \
  AUDIOWRT_PACKAGES_REF=main \
  FEATURES="mpd airplay" \
  CACHE_DIR=.cache/audiowrt \
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
- official release feed provenance;
- actual `audiowrt-packages` commit;
- selected features;
- resolved platform metadata;
- registered AudioWRT SDK sources;
- package-only versus source-build package classification;
- source-build dependency roots when applicable;
- SDK/ImageBuilder configuration;
- locally compiled AudioWRT APKs;
- image-size report.

## GitHub Actions

The repository exposes the manual **Build AudioWRT** workflow under the Actions tab. It uses `workflow_dispatch` only; pushes and pull requests do not consume GitHub-hosted runner time.

Its main inputs are:

```text
platform          default: tplink_tl-wdr4300-v1
openwrt_release   default: 25.12.5
features          default: empty (core only)
```

The builder image is fixed to `demonccc/openwrt-builder:latest` and is not shown as an editable workflow parameter.

`openwrt_release` is editable, but it must be an exact final release such as `25.12.6`; moving release branches and aliases are rejected.

## License

AudioWRT-specific GPL code in this repository is licensed under GPL-2.0-only unless stated otherwise. Software pulled from OpenWrt and external package feeds keeps its original license.
