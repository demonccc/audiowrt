<p align="center">
  <img src="assets/audiowrt-logo.svg" width="160" alt="AudioWRT">
</p>

# AudioWRT

AudioWRT is an audio-focused OpenWrt distribution that turns compatible OpenWrt devices into lightweight network-audio appliances.

AudioWRT does **not** maintain a fork of the OpenWrt source tree. A device profile pins the OpenWrt release and target, AudioWRT builds only the package layer it owns, and the matching official OpenWrt ImageBuilder assembles the final firmware.

## Current product model

AudioWRT is designed as a small appliance rather than a general-purpose router configuration. The current runtime model is:

```text
network controller
      |
      v
AudioWRT DLNA Renderer
      |
      v
codec/player registry
      |
      +--> USB Audio / ALSA
      |
      +--> Bluetooth A2DP Source
```

The public network-audio service is the AudioWRT DLNA/UPnP MediaRenderer. MPD and `upmpdcli` are not part of the default renderer path. AudioWRT native players register their codec/MIME capabilities and are selected per codec with automatic fallback to another compatible installed player.

The current LuCI experience is also AudioWRT-owned: the AudioWRT theme provides the product branding, sidebar navigation and monochrome control language while retaining LuCI/Bootstrap as the structural compatibility layer.

## Version policy

AudioWRT has its own distribution version in the repository-root `VERSION` file. It uses semantic versioning independently from both OpenWrt and individual package versions.

A build records at least:

- AudioWRT distribution version;
- AudioWRT commit;
- `audiowrt-packages` commit;
- exact OpenWrt release/profile/target/subtarget;
- SDK and ImageBuilder provenance;
- resolved package composition;
- generated AudioWRT APKs;
- image-size information.

Individual AudioWRT packages use stable package names, semantic `PKG_VERSION` values and numeric `PKG_RELEASE` revisions. OpenWrt-derived packages keep the upstream/OpenWrt release context selected by the firmware profile.

## Build model

Release profiles are pinned to an exact final OpenWrt release. The build uses:

```text
AudioWRT profile
      |
      +--> exact OpenWrt release + device profile
      |
      +--> official OpenWrt SDK
      |      +--> build selected AudioWRT APKs only
      |
      +--> official OpenWrt ImageBuilder
             +--> official release packages
             +--> locally built AudioWRT APKs
             +--> AudioWRT package add/remove policy
             v
          firmware
```

The canonical build environment is:

```text
demonccc/openwrt-builder:latest
```

AudioWRT has no separate Dockerfile and does not silently substitute another builder image.

Example:

```sh
make build \
  AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5
```

Useful local diagnostic inputs are:

```text
JOBS
VERBOSITY=normal|verbose|debug
LOG_FILE=<local path>
CACHE_DIR=<local download cache>
```

## Package groups

Firmware composition is based on **package groups**, not flavors.

`common` is applied automatically to every profile. A profile then selects one or more capability/runtime groups and may add or remove genuine device-specific exceptions.

Current selectable groups are:

- `minimal-usb-audio`
- `minimal-usb-bluetooth`
- `minimal-usb-audio-bluetooth`
- `usb-audio`
- `usb-bluetooth`
- `usb-audio-bluetooth`

The `minimal-*` groups include the constrained `minimal` runtime. The standard USB groups include the normal `standard` runtime. See [`config/package-groups/README.md`](config/package-groups/README.md) for the authoritative package-composition contract.

The constrained runtime currently uses AudioWRT-owned replacements where the compiled binary or footprint genuinely differs, including the minimal ALSA runtime, `audiowrt-dropbear`, `audiowrt-wpad` and the constrained Bluetooth stack. The standard runtime prefers normal OpenWrt providers.

## Reference device and profiles

The primary constrained reference device is the TP-Link TL-WDR4300 v1. The current reference Bluetooth build is:

```text
tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5
```

A separate constrained USB Audio profile is maintained for the same device.

The catalog also contains profiles for Raspberry Pi 3, Raspberry Pi 4, Linksys EA8300 and x86-64. Profiles are declarative YAML files under [`profiles/`](profiles/) and bind an OpenWrt device to ordered AudioWRT package groups.

Community profiles should remain data-only; runtime scripts and package-owned configuration belong in `demonccc/audiowrt-packages`.

## Provisioning and appliance networking

A fresh AudioWRT image starts with appliance-safe networking rather than an OpenWrt router default:

- initial hostname: `AudioWRT`;
- LAN: DHCP client;
- no default `192.168.1.1` LAN address;
- WAN disabled;
- no stock Wi-Fi SSID;
- radios disabled until provisioning/runtime configuration requires them.

Provisioning runs automatically near the end of boot. The connectivity preference is:

1. configured Wi-Fi client with link + IP;
2. LAN with link + IP;
3. temporary provisioning network if neither path is usable.

The temporary setup network uses:

```text
SSID: AudioWRT-<MAC suffix>
IPv4: 192.168.77.1/24
```

The setup AP is runtime-only. It must not create persistent Wi-Fi configuration that survives provisioning. Selecting a Wi-Fi network normally stores the SSID and lets the client choose the best matching access point instead of pinning a BSSID.

The provisioning UI and LuCI use the same AudioWRT branding and visual language.

## Audio output

AudioWRT supports two primary physical output paths:

- USB Audio Class / ALSA;
- Bluetooth A2DP Source for speakers and headphones.

Output selection is centralized by the AudioWRT audio layer. Player packages write PCM through the selected ALSA route instead of owning independent hardware-selection policy.

Bluetooth and USB Audio capability selection are expressed by package groups. The constrained WDR4300 Bluetooth profile removes heavier codecs/players where necessary to remain useful on 8 MB flash.

## DLNA Renderer

The AudioWRT renderer owns the public network-audio endpoint, playback status and codec/player selection. It advertises only codec capabilities that have a compatible installed player.

Home Assistant / Music Assistant and other UPnP controllers can therefore discover AudioWRT and send audio without requiring a full media framework on the device.

## Repository ownership

This repository owns:

- firmware profiles;
- package-group selection;
- build orchestration;
- provenance and validation;
- distribution documentation.

Reusable runtime packages and LuCI applications live in [`demonccc/audiowrt-packages`](https://github.com/demonccc/audiowrt-packages), including the renderer, native players, Bluetooth/audio services, provisioning components and AudioWRT LuCI theme.

## Build outputs

Firmware and build metadata are written below:

```text
output/<audiowrt-profile>/
```

A successful build must contain a real firmware image. If ImageBuilder completes without producing a supported image artifact, AudioWRT treats the build as failed and retains diagnostics rather than presenting an empty artifact as success.

## GitHub Actions

The repository provides the manual **Build AudioWRT** workflow. The selected profile determines the OpenWrt release and target; there is no separate caller-controlled OpenWrt-version input.

Important workflow inputs are the AudioWRT profile, the `audiowrt-packages` ref and the provisioning IPv4 address.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — build/runtime architecture and ownership boundaries.
- [`docs/8mb-functional-baseline.md`](docs/8mb-functional-baseline.md) — constrained WDR4300 product baseline.
- [`docs/build-diagnostics.md`](docs/build-diagnostics.md) — build troubleshooting and diagnostics.
- [`config/package-groups/README.md`](config/package-groups/README.md) — authoritative package-group composition.
- [`profiles/README.md`](profiles/README.md) — device-profile schema and contribution rules.

## License

AudioWRT-specific GPL code in this repository is licensed under GPL-2.0-only unless stated otherwise. Software pulled from OpenWrt and external package feeds keeps its original license.
