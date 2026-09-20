# AudioWRT package groups

AudioWRT firmware composition is based on package groups, not flavors.

`common` is the mandatory AudioWRT baseline and is applied automatically to every profile. It is not selected explicitly. It contains only functionality that is identical in every AudioWRT image; implementation choices such as standard vs constrained SSH, Wi-Fi supplicant, codec sets and network rendering do not belong there.

Reusable runtime groups:

- `minimal`: constrained-device runtime using AudioWRT-owned replacements only where a compiled binary really needs to differ.
- `standard`: ordinary OpenWrt runtime packages for devices where flash pressure is not the primary constraint.

Runtime mapping:

| Function | Minimal | Standard |
| --- | --- | --- |
| ALSA | `libaudiowrt-alsa-minimal` | `alsa-lib` |
| TLS | `libmbedtls21` | `libmbedtls21` |
| SSH server | `dropbear` | `dropbear` |
| Wi-Fi station | `audiowrt-wpad` | `wpad-basic-mbedtls` |
| Renderer + discovery | `audiowrt-renderer` | `audiowrt-renderer` |
| Native codec players | FLAC + MP3 | FLAC + MP3 + AAC + WAV |
| Renderer configuration | `luci-app-audiowrt-renderer` | `luci-app-audiowrt-renderer` |

`audiowrt-renderer` is the public network-audio service. One small daemon owns SSDP/DLNA, the UPnP MediaRenderer control services, minimal authoritative mDNS/DNS-SD for the AudioWRT hostname and LuCI service, codec/player autodetection, custom player overrides and playback status. A separate `umdns` daemon is not part of the default runtime.

The renderer discovers installed `audiowrt-player-*` packages at runtime and advertises only codecs that are actually available. Official players use `libuclient` in-process for HTTP/HTTPS streaming, decode directly with their codec library and write PCM through ALSA.

MPD and `upmpdcli` are no longer part of the default AudioWRT renderer stack. MPD remains installable as an optional external player and can be associated with a codec through the renderer LuCI custom-player override. A custom mapping takes precedence while the autodetected AudioWRT player remains registered as the fallback.

Selectable capability groups are:

- `minimal-usb-audio`
- `minimal-usb-bluetooth`
- `minimal-usb-audio-bluetooth`
- `usb-audio`
- `usb-bluetooth`
- `usb-audio-bluetooth`

Package groups may declare `include` entries to reuse another package group. Includes are resolved recursively before the current group's own `packages_add` / `packages_remove` entries are applied. Include cycles are rejected.

The three `minimal-*` groups include `minimal`. The three standard `usb-*` groups include `standard`. This keeps runtime implementation policy separate from USB audio/Bluetooth capability selection and avoids relying on include ordering to choose core implementations.

A profile selects the package group or groups it needs through `package_groups`. Package groups define package selection only. Device-specific exceptions belong in the profile's `packages_add` / `packages_remove` overrides.

Example:

```yaml
package_groups:
  - minimal-usb-bluetooth
```

Resolution order is:

1. automatic `common` baseline;
2. recursively included groups;
3. each selected group's own package changes;
4. device profile `packages_add` / `packages_remove` overrides.

Runtime files and package-specific configuration do not belong in this repository. They must be owned by a package under `audiowrt-packages`.

## Hardware responsibility

AudioWRT does not try to infer or enforce USB-host capability during the build. A profile maintainer must verify that the target hardware can expose an audio path suitable for the selected package group, such as USB Audio or a USB Bluetooth adapter. OpenWrt device metadata and the hardware documentation should be checked before publishing or using a profile.
