# AudioWRT Architecture

## Scope

AudioWRT is an appliance-oriented OpenWrt distribution. OpenWrt remains authoritative for hardware support, kernel ABI, target layout, toolchain and official release packages. AudioWRT owns the product runtime, package selection, provisioning flow, audio services and UI.

The distribution repository (`demonccc/audiowrt`) owns build orchestration and profiles. Reusable runtime packages live in `demonccc/audiowrt-packages`.

## Build contract

Every release profile pins one exact OpenWrt release and one OpenWrt device mapping.

```text
AudioWRT profile
   -> exact OpenWrt release
   -> target / subtarget / device profile
   -> official SDK
   -> official ImageBuilder
```

Release candidates, implicit branch aliases and caller-provided OpenWrt-version overrides are not part of a release profile. Snapshot profiles are explicitly named as snapshots.

AudioWRT does not maintain a forked OpenWrt source tree and does not generate a custom ImageBuilder.

## Package provenance

AudioWRT packages fall into three practical classes.

### OpenWrt-derived compiled packages

When AudioWRT genuinely changes an upstream/OpenWrt binary, the AudioWRT package derives from the canonical recipe belonging to the selected OpenWrt release and carries only the AudioWRT delta.

Examples include constrained replacements such as `audiowrt-busybox`, `audiowrt-wpad` and the minimized Bluetooth stack.

The selected OpenWrt context remains authoritative for source revision, patch set, hardening, target toolchain and ABI.

### Package-only/runtime packages

If AudioWRT changes policy, scripts, LuCI or runtime configuration but not the upstream compiled binary, the package is built as an AudioWRT package layer without recursively rebuilding its OpenWrt runtime dependencies.

### AudioWRT-owned source packages

Software without a canonical supported OpenWrt recipe may be owned directly by AudioWRT and compiled with the SDK selected by the device profile.

## Firmware composition

Firmware composition is based on package groups.

```text
common
  + minimal or standard runtime
  + USB Audio / Bluetooth capability group
  + device-specific profile overrides
```

`common` is automatic. A profile selects capability groups through `package_groups`.

The current groups are:

- `minimal-usb-audio`
- `minimal-usb-bluetooth`
- `minimal-usb-audio-bluetooth`
- `usb-audio`
- `usb-bluetooth`
- `usb-audio-bluetooth`

`config/package-groups/README.md` is the authoritative composition document.

## Runtime architecture

The public network-audio endpoint is the AudioWRT DLNA/UPnP MediaRenderer.

```text
UPnP/DLNA controller
        |
        v
  audiowrt-renderer
        |
        +--> codec/player registry
        |       |
        |       +--> native FLAC/WAV/LPCM/etc player
        |
        v
   AudioWRT ALSA route
      /        \
 USB Audio   BlueALSA
```

MPD and `upmpdcli` are not part of the default renderer path. They may be integrated as optional players only if they obey the common player contract and register their supported codecs.

The renderer owns:

- SSDP/DLNA discovery and MediaRenderer control;
- playback state exposed to LuCI;
- codec/MIME advertisement based on installed compatible players;
- per-codec preferred player selection and automatic fallback;
- the public network-facing rendering role.

Player and codec metadata are package-owned runtime registries rather than renderer-local hard-coded tables.

## Audio output ownership

Physical output selection belongs to the AudioWRT audio layer, not to individual players.

Supported output paths are primarily:

- USB Audio Class / ALSA;
- Bluetooth A2DP Source through BlueALSA.

Players decode/stream and write PCM to the AudioWRT-selected ALSA route.

## Provisioning and network ownership

AudioWRT boots as an appliance, not as a default NAT router.

Factory/runtime baseline:

- hostname `AudioWRT`;
- LAN as DHCP client;
- WAN disabled;
- no default `192.168.1.1` LAN address;
- no stock OpenWrt SSID;
- radios disabled until needed.

Provisioning preference order is:

1. persistent configured Wi-Fi client with link + IP;
2. LAN with link + IP;
3. temporary setup network.

The setup network uses `AudioWRT-<MAC suffix>` and `192.168.77.1/24` by default. Temporary AP state is runtime-only and must not be committed as persistent UCI Wi-Fi configuration.

The normal client profile stores the SSID and authentication policy. BSSID pinning is not the default: the Wi-Fi stack should choose the best matching access point for the selected network.

Provisioning and LuCI share the same AudioWRT branding and UI language.

## LuCI architecture

AudioWRT keeps LuCI as the administration framework but owns the product presentation through `luci-theme-audiowrt`.

The theme provides:

- final AudioWRT branding and favicon;
- left-side accordion navigation;
- active submenu state;
- monochrome forms and normal actions;
- semantic green for enabled state;
- semantic red for destructive/stop actions;
- card/layout consistency with provisioning.

Bootstrap remains the structural compatibility layer for LuCI widgets and pages.

## Constrained runtime

The WDR4300 reference target has only 8 MB flash, so its minimal runtime uses smaller AudioWRT-owned providers where the binary footprint or feature set must differ.

Examples include:

- minimized BusyBox applet set while retaining on-device diagnostics such as `vi`, `top` and `which`;
- `audiowrt-wpad` for the required hostap/supplicant paths;
- `audiowrt-dropbear` server-only SSH runtime;
- minimized Bluetooth/BlueALSA stack;
- constrained codec/player selection.

The constrained Bluetooth capability group additionally removes heavier player formats that do not justify their flash cost on that profile.

## Build flow

```text
1. validate AudioWRT profile
2. resolve exact OpenWrt release + target
3. obtain official SDK and ImageBuilder
4. resolve package groups and profile overrides
5. build only selected AudioWRT APKs
6. inject local APKs into official ImageBuilder
7. assemble firmware using official release repositories
8. record provenance, package plan and image-size diagnostics
```

A successful ImageBuilder invocation that produces no firmware image is treated as a failed build.

## Hardware ownership

OpenWrt remains authoritative for:

- target/subtarget/device definitions;
- kernel configuration and ABI;
- Ethernet/Wi-Fi/USB drivers and firmware;
- architecture/toolchain;
- target patches;
- image layout.

AudioWRT profiles describe required product capabilities; maintainers are responsible for choosing hardware that can provide the required physical audio path.

## Reproducibility

For a reproducible release build, pin an exact AudioWRT commit, an exact `audiowrt-packages` commit and an exact-release device profile. Snapshot profiles are intentionally moving builds.
