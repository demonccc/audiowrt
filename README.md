# AudioWRT

AudioWRT is an audio-focused OpenWrt distribution build system. It starts every build from a clean upstream OpenWrt checkout, keeps OpenWrt as the source of truth for hardware support, and layers a small AudioWRT appliance core plus reusable music packages.

## Repository boundary

AudioWRT intentionally splits distribution behavior from reusable audio functionality.

### This repository: `audiowrt`

Owns behavior that only makes sense when the whole device **is AudioWRT**:

- AudioWRT device identity and appliance state;
- Ethernet as DHCP client instead of a router-side LAN;
- first-boot `AudioWRT-XXXX` setup AP;
- Wi-Fi STA provisioning and WPS recovery;
- forwarding disabled;
- guided USB extension storage/extroot;
- `luci-app-audiowrt-core` for Network, Storage and System;
- the reproducible OpenWrt build and firmware package policy.

These packages live under [`package/`](package/) and are copied into the clean OpenWrt tree at build time. They are **not** published as generic OpenWrt add-ons.

### Reusable repository: `audiowrt-packages`

Owns functionality that is safe to add to an existing OpenWrt router without changing its network role:

- common audio state;
- USB DAC/ALSA output management;
- MPD;
- AirPlay;
- Spotify Connect/librespot;
- Bluetooth A2DP output/BlueALSA;
- runtime music-service extensions;
- audio-only `luci-app-audiowrt`.

When the full AudioWRT firmware is built, both layers are installed and their LuCI pages appear under one `AudioWRT` menu.

```text
AudioWRT
├── Overview       reusable audio UI
├── Output         reusable audio UI
├── Extensions     reusable audio UI
├── Network        distribution core only
├── Storage        distribution core only
└── System         distribution core only
```

## Core versus optional music services

The default firmware contains the appliance core and USB audio but does not require every music engine to fit in internal flash.

```text
Internal flash
└── AudioWRT Core
    ├── OpenWrt device drivers
    ├── AudioWRT provisioning/network role
    ├── USB Audio Class + ALSA
    ├── minimal LuCI
    ├── guided USB extension storage
    └── extension manager

Optional services
├── MPD
├── AirPlay
├── Spotify Connect
└── Bluetooth Audio
```

Services can be preinstalled with `FEATURES` when a device has enough flash, or installed later from the Extensions UI. If internal storage is too small, the AudioWRT-only Storage page can prepare a USB partition as extroot; the reusable extension manager itself never manipulates storage.

## Reference device

The initial reference device is TP-Link TL-WDR4300 v1:

```text
PLATFORM=tplink_tl-wdr4300-v1
OpenWrt target: ath79/generic
USB host: kmod-usb2 from the OpenWrt device profile
```

Core build:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  AUDIOWRT_PACKAGES_REF=feat/mvp-runtime
```

Preinstall selected services only if they fit:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  AUDIOWRT_PACKAGES_REF=feat/mvp-runtime \
  FEATURES="mpd spotify"
```

Available feature IDs are `mpd`, `airplay`, `spotify` and `bluetooth`; `FEATURES=all` requests all of them. OpenWrt's image-size check is authoritative and the build never silently drops a requested feature.

## Selecting a device

`PLATFORM` is the native OpenWrt device profile identifier. AudioWRT does not maintain a device database.

1. Open the [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/).
2. Search for the exact model and hardware revision.
3. Use its OpenWrt profile/device identifier as `PLATFORM`.
4. The build resolves target/subtarget from the exact OpenWrt source ref being built.

The [OpenWrt Table of Hardware](https://openwrt.org/toh/start) can be used to verify physical hardware details.

## USB gate

USB host support is mandatory for the initial AudioWRT architecture. Validation happens against the unmodified OpenWrt profile metadata **before** AudioWRT packages are added.

```text
USB confirmed -> continue
USB missing   -> fail
USB unknown   -> fail
```

The build never queries the OpenWrt website as a capability source.

## Build inputs

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_REF=openwrt-25.12 \
  AUDIOWRT_PACKAGES_REF=main \
  FEATURES="mpd airplay spotify bluetooth" \
  JOBS=8
```

- `OPENWRT_REF=stable` resolves the newest final upstream OpenWrt release by default.
- `AUDIOWRT_PACKAGES_REF=main` selects the reusable package feed.
- `FEATURES` is optional and empty by default.

## Build process

```text
Resolve OpenWrt ref
        ↓
Clone clean openwrt/openwrt
        ↓
Copy AudioWRT-only package/ into OpenWrt
        ↓
Add audiowrt-packages feed
        ↓
Generate OpenWrt metadata
        ↓
Resolve PLATFORM
        ↓
Validate USB host capability
        ↓
OpenWrt device packages
+ AudioWRT distribution core
+ reusable AudioWRT audio packages
+ optional FEATURES
- generic router packages
        ↓
Build firmware
        ↓
Firmware + manifest + image-size report
```

Build artifacts record the exact AudioWRT commit, OpenWrt commit, reusable package-feed commit, selected platform and selected features.

## First boot

AudioWRT derives a name such as `AudioWRT-A4F2`, keeps Ethernet as a DHCP client, and creates a temporary isolated Wi-Fi setup AP when a radio exists. Setup is served at `http://192.168.77.1/`. Successful provisioning switches to Wi-Fi STA mode; failed attempts restore the setup AP. After successful setup, normal Wi-Fi loss does not automatically reopen provisioning. Holding WPS for at least five seconds explicitly re-enters setup mode where supported.

## External storage

The AudioWRT core can prepare an unused USB partition as ext4 and configure OpenWrt extroot. The internal core remains the fallback if the external device is absent. This feature is deliberately distribution-only: installing `audiowrt-packages` on a normal OpenWrt router never formats or changes its storage layout.

## GitHub Actions policy

All workflows are manual `workflow_dispatch` workflows. Pushes and pull requests do **not** automatically consume GitHub-hosted runner time.

- `Validate AudioWRT`: fast script/metadata tests.
- `Build AudioWRT`: real firmware build, only when explicitly requested.

Local and manual CI builds use the same `make build` entry point.

## License

AudioWRT-owned GPL code is GPL-2.0-only unless stated otherwise. LuCI code uses Apache-2.0. OpenWrt and third-party package sources retain their upstream licenses.
