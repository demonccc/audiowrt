# AudioWRT package groups

AudioWRT firmware composition is based on package groups, not flavors.

`common` is the mandatory AudioWRT baseline and is applied automatically to every profile. It is not selected explicitly. It contains product-wide functionality that is identical in every AudioWRT image, including provisioning, the native renderer, the AudioWRT LuCI applications and the AudioWRT theme.

Reusable runtime groups:

- `minimal`: constrained-device runtime using AudioWRT-owned replacements where the compiled feature set or footprint genuinely needs to differ.
- `standard`: ordinary OpenWrt runtime packages for devices where flash pressure is not the primary constraint.

Runtime mapping:

| Function | Minimal | Standard |
| --- | --- | --- |
| ALSA | `libaudiowrt-alsa-minimal` | `alsa-lib` |
| TLS | `libmbedtls21` | `libmbedtls21` |
| SSH server | `audiowrt-dropbear` | `dropbear` |
| Wi-Fi station | `audiowrt-wpad` | `wpad-basic-mbedtls` |
| Network clients | `audiowrt-network-client` + `audiowrt-wifi-client` | same AudioWRT client layer |
| Network configuration UI | `luci-app-audiowrt-network-client` | `luci-app-audiowrt-network-client` |
| Renderer + discovery | `audiowrt-renderer` | `audiowrt-renderer` |
| Renderer configuration | `luci-app-audiowrt-renderer` | `luci-app-audiowrt-renderer` |
| LuCI theme | `luci-theme-audiowrt` | `luci-theme-audiowrt` |

`audiowrt-renderer` is the public network-audio service. It owns SSDP/DLNA, the UPnP MediaRenderer control services, lightweight discovery required by the appliance, playback status and player selection.

Player packages register their codec/MIME/extension support and executable in AudioWRT runtime registries. Codec capability and installed-player metadata are kept separate so both the renderer and local playback can resolve the same installed capabilities while keeping their own preferred-player settings. The renderer advertises only codecs that have at least one compatible installed player.

MPD and `upmpdcli` are not part of the default renderer stack. MPD, VLC or another engine can be integrated through a wrapper that obeys the common foreground `player <URL>` contract and registers its supported codecs. LuCI selects the preferred player per codec; compatible alternatives remain automatic fallbacks.

Selectable capability groups are:

- `minimal-usb-audio`
- `minimal-usb-bluetooth`
- `minimal-usb-audio-bluetooth`
- `usb-audio`
- `usb-bluetooth`
- `usb-audio-bluetooth`

Package groups may declare `include` entries to reuse another package group. Includes are resolved recursively before the current group's own `packages_add` / `packages_remove` entries are applied. Include cycles are rejected.

The three `minimal-*` groups include `minimal`. The three standard `usb-*` groups include `standard`. This keeps runtime implementation policy separate from USB Audio/Bluetooth capability selection.

`minimal-usb-bluetooth` removes the heavier MP3/AAC/M4A players from the shared minimal set to reduce flash use on constrained Bluetooth devices. Other groups retain the formats selected by their runtime policy.

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

AudioWRT does not infer every physical audio capability from OpenWrt metadata. A profile maintainer must verify that the target hardware can expose the audio path required by the selected package group, such as USB Audio or a supported USB Bluetooth adapter.
