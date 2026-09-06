# AudioWRT Architecture

## Two-layer model

AudioWRT has two deliberately separate ownership domains.

```text
audiowrt
  distribution-only behavior
  ├── build system
  ├── audiowrt-core
  ├── audiowrt-provisioning
  ├── audiowrt-storage
  └── luci-app-audiowrt-core

                consumes
                   ↓

audiowrt-packages
  reusable OpenWrt audio functionality
  ├── audiowrt-audio
  ├── audiowrt-usb-audio
  ├── audiowrt-extensions
  ├── audiowrt-mpd
  ├── audiowrt-airplay
  ├── audiowrt-spotify / librespot
  ├── audiowrt-bluetooth / bluez-alsa
  └── luci-app-audiowrt
```

The rule is simple: **if a feature changes OpenWrt's role as a router/system, it belongs in `audiowrt`; if it only adds audio capability, it belongs in `audiowrt-packages`.**

## Distribution core

`audiowrt-core` owns identity and appliance state only. `audiowrt-provisioning` owns client-only networking, first boot and recovery. `audiowrt-storage` owns guided external extroot. This prevents any of those behaviors from being installed accidentally on an existing OpenWrt router through the reusable feed.

`luci-app-audiowrt-core` extends the reusable AudioWRT menu with Network, Storage and System pages.

## Reusable audio layer

The reusable layer does not write `network`, `wireless`, `dhcp` or firewall configuration.

Music engines consume the logical ALSA `default` output. `audiowrt-usb-audio` can map it to a USB DAC; `audiowrt-bluetooth` can map it to a BlueALSA A2DP device. MPD, AirPlay and librespot therefore do not need board-specific audio configuration.

The extension manager installs AudioWRT wrapper packages with `apk`. Storage policy is intentionally outside the reusable manager; on standard OpenWrt it simply uses whatever writable overlay the system already has.

## Bluetooth

Bluetooth output uses OpenWrt BlueZ plus the lightweight BlueALSA bridge. The AudioWRT feed carries BlueALSA because OpenWrt 25.12 does not provide it in the standard packages feed. The package includes big-endian fixes relevant to MIPS/ath79. `audiowrt-bluetooth` provides discovery, pairing, connection and ALSA-default selection.

## Spotify

Spotify Connect uses a packaged librespot 0.8.0 build with OpenWrt's Rust toolchain, the ALSA backend, rustls and pure-Rust mDNS. The AudioWRT wrapper sets the receiver name and ALSA `default` output and disables the audio cache. Spotify Premium is required by librespot.

## Platform and USB ownership

OpenWrt remains authoritative for board definitions, kernel/device tree, Ethernet/switch drivers, Wi-Fi firmware and USB host controllers. `PLATFORM` is an OpenWrt profile supplied at build time; AudioWRT has no platform database.

USB host capability is validated from the unmodified OpenWrt target metadata before AudioWRT packages are selected. Missing or unknown USB support is a hard failure.

## Low-flash devices

The default firmware contains core functionality but optional music engines remain separate. `FEATURES` can preinstall engines for devices with enough flash. OpenWrt's own image-size limit is authoritative; oversized requested builds fail.

On constrained AudioWRT devices, guided USB extroot can expand the writable package overlay while preserving the internal core as a fallback.

## CI

GitHub-hosted workflows are manual-only. No push or pull-request trigger is configured. Local builds and manually dispatched builds use the same entry point.
