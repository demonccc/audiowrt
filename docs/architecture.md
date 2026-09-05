# Architecture

## Repository split

AudioWRT uses two repositories with separate responsibilities.

### `audiowrt`

The distribution source tree. Stable AudioWRT branches are based directly on the corresponding OpenWrt stable branches and contain only the downstream changes required to turn OpenWrt into an audio appliance.

### `audiowrt-packages`

A reusable OpenWrt feed containing AudioWRT-specific packages and LuCI applications. These packages are intentionally usable from both AudioWRT and standard OpenWrt installations.

## Distribution boundaries

AudioWRT does not delete router functionality from the OpenWrt source tree. Instead, firmware images are built with a minimal package selection focused on:

- Ethernet and Wi-Fi client networking
- first-boot provisioning
- DHCP client and local setup DHCP/DNS
- mDNS discovery
- web management
- USB and storage support
- ALSA and audio transports
- package management

Router-oriented features such as NAT, firewall management, port forwarding, multi-WAN, PPP server use cases, VPN server features and advanced routing are excluded from the default image unless required by a target or dependency.

## Provisioning state model

### Unprovisioned

The device creates a temporary setup AP named `AudioWRT-XXXX`, where the suffix is derived from a stable device identifier. A minimal DHCP/DNS service and the AudioWRT web setup page are available only on this local setup network.

### Provisioned

The setup AP is disabled. Wi-Fi runs as a station/client and Ethernet runs as a DHCP client. The device is discoverable by mDNS.

### Connectivity lost

The device does not reopen the setup AP automatically. Provisioning mode must be re-entered explicitly, preferably through a hardware button supported by the target.

## Audio architecture

Audio services are optional packages built on a shared core. The initial output path is ALSA with USB Audio Class devices. Additional transports and services are layered above that core.

```text
Spotify / MPD / AirPlay / Radio
              |
             ALSA
              |
       USB Audio / future outputs
```

## Versioning

Each supported OpenWrt stable line has a matching AudioWRT branch. Downstream commits should remain small, ordered and easy to reapply when a new OpenWrt stable line is introduced.
