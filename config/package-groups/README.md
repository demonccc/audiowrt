# AudioWRT package groups

AudioWRT firmware composition is based on package groups. `common` is applied automatically to every AudioWRT profile; selectable groups add runtime/capability policy.

## Common baseline

The common AudioWRT distribution baseline includes provisioning, the native DLNA renderer, the AudioWRT LuCI applications, the reusable AudioWRT theme and the explicit `audiowrt-distro-branding` layer.

The constrained common base selects:

- `busybox-udhcpd-tailored`, which provides both `busybox` and `udhcpd`;
- `luci-mod-status-tailored`, which provides `luci-mod-status` without the unused constrained-device status dependencies.

Device identity is part of `audiowrt-core`; there is no separate identity package.

## Runtime mapping

| Function | Minimal | Standard |
| --- | --- | --- |
| ALSA | `alsa-lib-trimmed` | `alsa-lib` |
| TLS | `libmbedtls21` | `libmbedtls21` |
| SSH server | `dropbear-trimmed` | `dropbear` |
| Wi-Fi station / setup AP | `hostapd-wpa-supplicant-tailored` | `wpad-basic-mbedtls` |
| Network clients | `audiowrt-network-client` + `audiowrt-wifi-client` | same AudioWRT client layer |
| DLNA Renderer + discovery | `audiowrt-dlna-renderer` | `audiowrt-dlna-renderer` |
| LuCI theme | `luci-theme-audiowrt` | `luci-theme-audiowrt` |
| Distribution branding | `audiowrt-distro-branding` | `audiowrt-distro-branding` |

`audiowrt-dlna-renderer` owns SSDP/DLNA, UPnP MediaRenderer services, lightweight discovery, playback status and player selection. It does not require MPD or upmpdcli.

Player packages remain intentionally granular. Codec capability and installed-player metadata are shared through `libaudiowrt-player`; each consumer keeps its own preferred-player settings.

`audiowrt-player-mpd` is an optional integration package for an independently installed OpenWrt MPD provider. It does not build or replace MPD. Both `mpd-mini` and `mpd-full` provide the `mpd` capability.

The obsolete `audiowrt-minimal-upmpdcli` package is not part of any runtime group.

## Bluetooth mapping

Minimal Bluetooth profiles select:

- `dbus-trimmed`;
- `kmod-bluetooth-trimmed`;
- `bluez-trimmed` through the AudioWRT Bluetooth dependency chain;
- `sbc-trimmed` and ported `bluez-alsa` as required by that chain;
- `audiowrt-bluetooth` as the AudioWRT integration layer.

Standard Bluetooth profiles keep the official OpenWrt Bluetooth kernel packages while retaining `dbus-trimmed` and the reusable AudioWRT Bluetooth integration.

## Selectable groups

- `minimal-usb-audio`
- `minimal-usb-bluetooth`
- `minimal-usb-audio-bluetooth`
- `usb-audio`
- `usb-bluetooth`
- `usb-audio-bluetooth`

The three `minimal-*` groups include `minimal`; the three standard `usb-*` groups include `standard`.

Package groups may recursively include another group. Includes are resolved before the current group's `packages_add` / `packages_remove` entries. Include cycles are rejected.

Resolution order:

1. automatic `common` baseline;
2. recursively included groups;
3. selected group package changes;
4. profile-specific `packages_add` / `packages_remove` overrides.

Runtime files and package-specific configuration belong in `audiowrt-packages`, not in firmware profile definitions.
