# AudioWRT package groups

AudioWRT firmware composition is based on package groups, not flavors.

`common` is the mandatory AudioWRT baseline and is applied automatically to every profile. It is not selected explicitly. It contains only functionality that is identical in every AudioWRT image; implementation choices such as standard vs constrained SSH, Wi-Fi supplicant, UPnP/DLNA rendering and mDNS do not belong there.

Reusable runtime groups:

- `minimal`: constrained-device runtime using AudioWRT-owned replacements where reducing flash usage matters.
- `standard`: ordinary OpenWrt runtime packages for devices where flash pressure is not the primary constraint.

Runtime mapping:

| Function | Minimal | Standard |
| --- | --- | --- |
| ALSA | `audiowrt-minimal-alsa` | `alsa-lib` |
| TLS | `audiowrt-minimal-mbedtls` | `libmbedtls21` |
| SSH server | `audiowrt-dropbear` | `dropbear` |
| Wi-Fi station | `audiowrt-wpa-supplicant` | `wpad-basic-mbedtls` |
| MPD backend | `audiowrt-minimal-mpd` | `mpd-mini` |
| UPnP/DLNA renderer | `audiowrt-minimal-upmpdcli` | `upmpdcli` |
| mDNS / `.local` | `umdns` | `umdns` |

The renderer is the public network-audio interface. MPD is an internal playback backend and is configured by `audiowrt-mpd` to listen on loopback. Minimal builds advertise and decode FLAC + MP3; standard builds use the codec support provided by the official OpenWrt MPD/upmpdcli packages.

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
