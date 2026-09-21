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
| Native codec players | FLAC + MP3 + WAV | FLAC + MP3 + WAV + Vorbis + AAC |
| Renderer configuration | `luci-app-audiowrt-renderer` | `luci-app-audiowrt-renderer` |

`audiowrt-renderer` is the public network-audio service. One small daemon owns SSDP/DLNA, the UPnP MediaRenderer control services, minimal authoritative mDNS/DNS-SD for the AudioWRT hostname and LuCI service, the UCI codec/player registry, default/fallback player selection and playback status. A separate `umdns` daemon is not part of the default runtime.

Player packages register codec MIME/extension metadata and their executable in `/etc/config/audiowrt`. The renderer hot-reloads that registry and advertises only codecs with an available compatible player. Official players use `libuclient` in-process for HTTP/HTTPS streaming, decode directly with their codec library and write PCM through ALSA.

MPD and `upmpdcli` are no longer part of the default AudioWRT renderer stack. MPD, VLC or another engine can be integrated through a wrapper that obeys the common `player <URL>` foreground contract and registers its supported codecs. LuCI selects the default player per codec; other compatible players remain automatic fallbacks.

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
