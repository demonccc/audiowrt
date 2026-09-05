# AudioWRT

AudioWRT is an audio-focused OpenWrt distribution for turning compatible network devices into lightweight, reliable network audio players.

AudioWRT keeps OpenWrt as the hardware, kernel, networking and package-management foundation while changing the product focus from routing to network audio.

## Project model

AudioWRT is maintained as a downstream OpenWrt source tree with one branch per supported OpenWrt stable line.

- `main`: project metadata, bootstrap tooling and distribution documentation.
- `audiowrt-25.12`: AudioWRT based on the OpenWrt 25.12 stable branch.
- future stable lines will use equivalent `audiowrt-<version>` branches.

Audio functionality is developed separately in [`demonccc/audiowrt-packages`](https://github.com/demonccc/audiowrt-packages) and consumed as an OpenWrt feed.

## Product principles

- Audio appliance first, router second.
- Keep the upstream OpenWrt source tree intact whenever possible.
- Remove router-oriented packages from the firmware image rather than deleting their source code.
- Ethernet operates as a network client by default.
- Wi-Fi operates as a station after provisioning.
- First boot uses a minimal temporary Wi-Fi provisioning AP.
- Advanced routing, NAT and firewall features are not part of the default product experience.
- The package manager remains available underneath the product so audio extensions and device drivers can be installed without rebuilding firmware.
- The default web UI exposes only Audio, Network and essential System controls.

## Initial networking contract

1. Ethernet uses DHCP client mode.
2. Wi-Fi normally uses station/client mode.
3. An unprovisioned device creates a temporary `AudioWRT-XXXX` setup AP.
4. The setup AP exists only for provisioning and does not route Internet traffic.
5. After successful Wi-Fi provisioning, the setup AP is disabled.
6. Losing a configured Wi-Fi network does not automatically reopen the setup AP.
7. A hardware button may explicitly re-enter provisioning mode.
8. mDNS provides local discovery without requiring the user to know the device IP address.

## Package feed

The AudioWRT source branch includes the following feed:

```text
src-git audiowrt https://github.com/demonccc/audiowrt-packages.git
```

## Status

AudioWRT is in early development. The first milestone is a minimal OpenWrt 25.12 based image with client networking, first-boot Wi-Fi provisioning, USB audio and the AudioWRT LuCI shell.

## License

AudioWRT follows the licensing of the OpenWrt source tree. Project-specific GPL code is licensed under GPL-2.0-only unless stated otherwise. Individual upstream components retain their original licenses.
