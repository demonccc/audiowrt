# AudioWRT

AudioWRT is an audio-focused OpenWrt build system for turning compatible OpenWrt devices into lightweight, reliable network audio players.

AudioWRT does **not** fork or vendor the OpenWrt source tree. Each build starts from a clean OpenWrt checkout, lets OpenWrt resolve the selected device and all hardware-specific packages, then applies the AudioWRT package policy, filesystem overlay and audio packages.

## Design principles

- OpenWrt remains the source of truth for device support, kernel configuration and hardware-specific packages.
- AudioWRT only defines what is common to the audio appliance.
- Router-oriented packages are removed from the firmware image, not from the OpenWrt source tree.
- The selected OpenWrt device profile controls board-specific drivers and firmware.
- USB host support is mandatory for the initial AudioWRT architecture.
- A build fails when USB host capability cannot be confirmed from the selected OpenWrt device profile.
- The same build command is used locally and in GitHub Actions.
- OpenWrt versions are build inputs, not AudioWRT branches.

## Hardware requirements

AudioWRT currently requires:

- a device supported by OpenWrt;
- at least one usable USB host interface;
- enough flash and RAM for the selected AudioWRT package set;
- Ethernet and/or Wi-Fi connectivity.

USB is intentionally a hard requirement for the first AudioWRT generation because USB Audio Class devices are the primary audio-output path.

The build validates USB support from the OpenWrt source metadata for the selected device profile. It does **not** query the OpenWrt website during the build. If OpenWrt does not expose a recognized USB host package for the selected device profile, the build stops rather than guessing.

## Selecting a platform

`PLATFORM` is the OpenWrt **device profile identifier**.

The easiest way to find it is:

1. Open the [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/).
2. Search for your exact device model and hardware revision.
3. Open the device entry.
4. Use the OpenWrt profile/device identifier as `PLATFORM`.

You can also use the [OpenWrt Table of Hardware](https://openwrt.org/toh/start) to verify hardware details such as USB availability before building.

Example:

```text
Device: GL.iNet GL-MT6000
OpenWrt profile: glinet_gl-mt6000
```

Build it with:

```sh
make build PLATFORM=glinet_gl-mt6000
```

AudioWRT discovers the OpenWrt target and subtarget from OpenWrt's own generated target metadata. There is no AudioWRT platform database to maintain.

## OpenWrt version selection

By default, AudioWRT resolves `stable` to the newest final OpenWrt release tag available upstream.

```sh
make build PLATFORM=glinet_gl-mt6000
```

You can override the OpenWrt ref with any branch, tag or commit that exists in the upstream repository:

```sh
make build \
  PLATFORM=glinet_gl-mt6000 \
  OPENWRT_REF=openwrt-25.12
```

or:

```sh
make build \
  PLATFORM=glinet_gl-mt6000 \
  OPENWRT_REF=v25.12.5
```

`OPENWRT_REF=stable` is the default.

## Build process

A build performs the following steps:

```text
Resolve OpenWrt ref
        |
        v
Clone openwrt/openwrt
        |
        v
Add AudioWRT package feed
        |
        v
Generate OpenWrt target metadata
        |
        v
Resolve PLATFORM -> target/subtarget/profile
        |
        v
Validate USB host support
        |
        v
Let OpenWrt generate the device configuration
        |
        v
Add AudioWRT packages
        |
        v
Remove router-oriented packages
        |
        v
Apply AudioWRT filesystem overlay
        |
        v
Build OpenWrt
        |
        v
Copy firmware and build manifest to output/
```

## Package policy

AudioWRT keeps two generic package lists:

- [`config/packages.add`](config/packages.add): packages that AudioWRT requires on top of the selected OpenWrt device profile.
- [`config/packages.remove`](config/packages.remove): router-oriented packages that must not be present in the final firmware.

OpenWrt device packages are never replaced with a custom AudioWRT platform definition. Board-specific Wi-Fi firmware, Ethernet drivers, USB host controllers and other hardware dependencies remain OpenWrt's responsibility.

After `make defconfig`, AudioWRT validates both lists. The build fails if a required package cannot be enabled or if a forbidden package is pulled back in by a dependency.

## Filesystem overlay

Everything under [`files/`](files/) is copied into OpenWrt's build-root overlay before compilation.

Use this directory for AudioWRT defaults and files that belong in the firmware image, for example:

```text
files/
└── etc/
    ├── banner
    ├── config/
    └── uci-defaults/
```

Runtime services that belong to reusable audio functionality should normally live in [`audiowrt-packages`](https://github.com/demonccc/audiowrt-packages), not in this repository.

## AudioWRT package feed

The build automatically adds:

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git
```

The package repository can also be used independently from AudioWRT on a standard OpenWrt installation.

## Local build

Requirements are the normal OpenWrt source-build requirements plus Git and Python 3.

```sh
git clone https://github.com/demonccc/audiowrt.git
cd audiowrt

make build PLATFORM=glinet_gl-mt6000
```

Optional variables:

```sh
make build \
  PLATFORM=glinet_gl-mt6000 \
  OPENWRT_REF=openwrt-25.12 \
  JOBS=8
```

The OpenWrt source checkout is created under `.work/` and firmware artifacts are copied to `output/`.

Clean the local build workspace with:

```sh
make clean
```

## GitHub Actions

The `Build AudioWRT` workflow is manually runnable and accepts:

- `platform`: required OpenWrt device profile identifier;
- `openwrt_ref`: optional branch, tag or commit, defaulting to `stable`;
- `jobs`: optional parallel build job count.

The workflow calls the same `make build` entry point used locally and uploads the resulting `output/` directory as an artifact.

## Networking direction

The initial AudioWRT runtime model is intentionally smaller than a normal router firmware:

- Ethernet: DHCP client.
- Wi-Fi: station/client during normal operation.
- First boot: temporary minimal Wi-Fi provisioning AP.
- No normal NAT/router role.
- No normal firewall management UI.
- mDNS for local discovery.
- Package management remains available underneath the appliance so drivers and audio extensions can be installed when needed.

The provisioning implementation is tracked separately from the build-system architecture.

## Repository roles

- [`demonccc/audiowrt`](https://github.com/demonccc/audiowrt): reproducible distribution build, package policy, defaults and image overlay.
- [`demonccc/audiowrt-packages`](https://github.com/demonccc/audiowrt-packages): reusable OpenWrt packages and LuCI applications for AudioWRT functionality.

## License

AudioWRT-specific GPL code in this repository is licensed under GPL-2.0-only unless stated otherwise. Software pulled from OpenWrt and external package feeds keeps its original license.
