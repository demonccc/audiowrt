# AudioWRT

AudioWRT is an audio-focused OpenWrt distribution that turns compatible OpenWrt devices into lightweight network audio appliances.

AudioWRT does not maintain a fork of the OpenWrt source tree. Every firmware
profile names and declares its OpenWrt base, uses the matching official SDK and
ImageBuilder, builds the AudioWRT layer, and assembles the final image from
official binaries plus locally produced AudioWRT APKs.

## OpenWrt version policy

The OpenWrt source and version are part of the profile itself and must also be
visible in its ID. Stable profiles use an exact final release, for example
`tplink-tl-wdr4300-v1-minimal-25.12.5`. Snapshot profiles use the explicit
`-snapshot` suffix and are treated as moving/experimental builds. Branch aliases,
release candidates and implicit version overrides are not accepted.

Moving a device to another OpenWrt release therefore creates a separately named
profile that can be built and tested without changing the known-good one.

## Build model

AudioWRT follows the release-binary principle used by `release-patched` in [`demonccc/openwrt-builder`](https://github.com/demonccc/openwrt-builder), but AudioWRT does not patch OpenWrt kernel or target sources and does not generate a custom ImageBuilder.

```text
Exact OpenWrt release tag (for example v25.12.5)
                |
                v
Clean source checkout for device metadata only
                |
                +--> resolve AudioWRT profile -> OpenWrt profile/target/subtarget
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
  AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-25.12.5
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
  AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-25.12.5 \
  JOBS=1 \
  VERBOSITY=debug \
  LOG_FILE=logs/wdr4300.log
```

`LOG_FILE` is local-only. It captures the Docker pull and the complete container output while still showing the same stream in the terminal. The path must stay outside `.work/` and `output/` because those directories are recreated during builds.

The builder's persistent-download-cache pattern also applies to AudioWRT. Local builds can opt in with:

```sh
make build \
  AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-25.12.5 \
  CACHE_DIR=.cache/audiowrt
```

When enabled, AudioWRT reuses the exact-release SDK archive, the exact-release ImageBuilder archive, and OpenWrt package/source downloads. Compilation state is still recreated on every build. `.cache/` is ignored by Git and `make clean` does not remove it.

For repeated troubleshooting, combine both features:

```sh
make build \
  AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-25.12.5 \
  CACHE_DIR=.cache/audiowrt \
  JOBS=1 \
  VERBOSITY=debug \
  LOG_FILE=logs/wdr4300.log
```

GitHub Actions does not expose either a log-file or cache input. Hosted jobs remain clean and ephemeral, and the Actions job already retains its complete console log. The workflow also uploads whatever build diagnostics were produced when a build fails, while a successful build must contain at least one real firmware image.

The latest `openwrt-builder` stabilization changes how `release-patched` handles SDK host tools and generated custom ImageBuilders. AudioWRT does not need equivalent host-tool replacement logic because it uses the official SDK to build its package layer and the official ImageBuilder to assemble the firmware directly.

## Flavors and device profiles

AudioWRT separates package policy from hardware selection. A **flavor** defines
the common capability/size tier; a **device profile** combines one OpenWrt
device with one flavor and any device-specific package exceptions.

| Flavor | Intended target | Runtime providers | Included services |
|---|---|---|---|
| `minimal` | constrained 8 MB devices | AudioWRT minimal ALSA, Mbed TLS and Bluetooth kernel variants | USB Audio, Bluetooth A2DP and essential UI |
| `standard` | devices with normal flash headroom | unmodified OpenWrt infrastructure packages | minimal capabilities plus MPD and storage |
| `full` | large-flash devices | unmodified OpenWrt infrastructure packages | all AudioWRT services and storage |

Flavor definitions live in `config/flavors/`. Buildable profiles are declarative
YAML files in `profiles/`, for example
`tplink-tl-wdr4300-v1-minimal-25.12.5.yaml`. The profile records the OpenWrt
source/version, profile, target, subtarget, flavor, validation status and optional package
add/remove overrides. The build derives OpenWrt's `PROFILE` from this file; it
is no longer a separate caller-controlled input.

The default profile is `tplink-tl-wdr4300-v1-minimal-25.12.5`. The minimal functional
core includes:

- AudioWRT appliance identity;
- Ethernet DHCP-client behavior;
- temporary Wi-Fi provisioning AP and STA onboarding;
- USB Audio Class and ALSA output management;
- Bluetooth A2DP Source output;
- minimal LuCI (`luci-base` + AudioWRT applications);
- AudioWRT extension management.

Local USB storage/extroot, MPD, AirPlay and Spotify Connect are deliberately
absent from the minimal flavor. `standard` adds MPD and storage; `full` adds
the complete AudioWRT service set. Package composition is controlled only by
the selected profile—there is no second build-time feature list.

Bluetooth is a mandatory output capability for the current reference baseline rather than an optional feature. Its current BlueZ/BlueALSA implementation remains included so firmware-size reports expose its actual cost on constrained devices.

OpenWrt ImageBuilder enforces the selected device's image-size limit. AudioWRT does not silently drop profile packages. AudioWRT additionally treats a successful ImageBuilder command that produces no firmware image as a failed build. On constrained devices, larger services can instead be installed later through AudioWRT Extensions and optional USB extension storage.

## Reference device

The initial reference/test device is the TP-Link TL-WDR4300 v1:

```text
AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-25.12.5
```

Example core build:

```sh
make build \
  AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-25.12.5
```

The WDR4300 is a reference target only. AudioWRT profiles reference OpenWrt's
hardware database; device definitions, drivers, firmware and base package
choices remain OpenWrt responsibilities.

Initial candidate profiles are included for x86-64, Raspberry Pi 3,
Raspberry Pi 4, TP-Link Archer A9 v6 and Linksys EA8300. Candidate means the
mapping is valid but still needs a successful build and hardware test before
being promoted to `tested`. Raspberry Pi 3 and 4 intentionally use different
profiles: both are 64-bit ARM, but OpenWrt builds them as `bcm2710` and
`bcm2711`, respectively.

Community profiles are submitted as one YAML file through a pull request. They
do not contain executable shell code or duplicate flavor package lists.

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

Every package maintained by AudioWRT lives in [`demonccc/audiowrt-packages`](https://github.com/demonccc/audiowrt-packages). This repository owns only firmware profiles, package selection, build orchestration and validation:

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
AUDIOWRT_PROFILE         device + flavor profile ID
                         (default tplink-tl-wdr4300-v1-minimal-25.12.5)
AUDIOWRT_PACKAGES_REF    reusable package-feed branch/tag/commit (default main)
JOBS                     package build parallelism
VERBOSITY                normal, verbose or debug
LOG_FILE                 optional local-only diagnostic log path
CACHE_DIR                optional local-only persistent download cache
```

The Docker builder image is intentionally not an input.

For example:

```sh
make build \
  AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-25.12.5 \
  AUDIOWRT_PACKAGES_REF=main \
  CACHE_DIR=.cache/audiowrt \
  JOBS=8 \
  VERBOSITY=verbose
```

## Build outputs

Firmware is written under:

```text
output/<audiowrt-profile>/
```

The output also records:

- `BUILD_INFO`;
- `manifest.json`;
- exact OpenWrt commit;
- exact SDK and ImageBuilder URLs;
- official release feed provenance;
- actual `audiowrt-packages` commit;
- resolved flavor and package composition;
- resolved platform metadata;
- registered AudioWRT SDK sources;
- package-only versus source-build package classification;
- source-build dependency roots when applicable;
- SDK/ImageBuilder configuration;
- locally compiled AudioWRT APKs;
- image-size report.

If ImageBuilder produces no `.bin`, `.img`, `.img.gz`, `.ubi` or `.itb` firmware files, AudioWRT writes the diagnostic size report and fails the build instead of presenting an empty firmware artifact as success.

## GitHub Actions

The repository exposes the manual **Build AudioWRT** workflow under the Actions tab. It uses `workflow_dispatch` only; pushes and pull requests do not consume GitHub-hosted runner time.

Its main inputs are:

```text
audiowrt_profile      default: tplink-tl-wdr4300-v1-minimal-25.12.5
audiowrt_packages_ref  default: main
```

The builder image is fixed to `demonccc/openwrt-builder:latest` and is not shown as an editable workflow parameter.

The workflow does not expose a separate OpenWrt version parameter; the selected
profile is the complete build contract.

## License

AudioWRT-specific GPL code in this repository is licensed under GPL-2.0-only unless stated otherwise. Software pulled from OpenWrt and external package feeds keeps its original license.
