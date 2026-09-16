# AudioWRT flavors

A flavor is a reusable **base package set**, not a complete immutable firmware
definition. Flavors provide the smallest coherent starting point for a class of
devices. A device profile selects one flavor and may then add or remove packages
for a particular device, installation, or use case.

The final package set is resolved in this order:

1. the selected flavor's `packages.add` and `packages.remove` files;
2. the profile's `packages_add` and `packages_remove` overrides.

Profile overrides have the final say. Adding a package in `packages_add` cancels
its removal from the flavor, and removing a package in `packages_remove` cancels
its addition from the flavor. This makes it possible, for example, to use
`minimal-usb-bluetooth` as a base and add an optional package in a profile:

```yaml
packages_add:
  - rtl8761b-firmware
packages_remove: []
```

Profiles must contain only genuine device or deployment-specific overrides. Do
not copy a complete flavor package list into a profile. Shared package policy
belongs here, in the flavor.

## Choosing a flavor

Choose the base according to the available flash before adding optional
packages. The estimates below are planning values for the WDR4300/ath79
reference target, OpenWrt 25.12.5, and the normal 256 KiB SquashFS block size.
They include the flavor composition but not arbitrary profile additions.
ImageBuilder's final image-size check is authoritative.

| Flavor | Base capability | Estimated compressed rootfs | Practical flash target |
|---|---|---:|---:|
| `usb-audio` | USB Audio, Wi-Fi and UI; no Bluetooth | ~3.6–4.0 MiB | 8 MB |
| `minimal-usb-bluetooth` | Minimal Bluetooth A2DP, Wi-Fi, SSH, UI and BusyBox udhcpd | ~4.4–5.0 MiB | 8 MB, tight |
| `minimal-usb-bluetooth-audio` | Minimal Bluetooth plus standard USB Audio | ~4.9–5.3 MiB | 16 MB |
| `usb-bluetooth` | Standard OpenWrt Bluetooth plus Wi-Fi and UI | ~5.5–6.0 MiB | 16 MB |
| `usb-bluetooth-audio` | Standard Bluetooth plus standard USB Audio | ~5.8–6.4 MiB | 16 MB |

An 8 MB flash chip does not provide 8 MiB for the root filesystem: the
bootloader, kernel, metadata and image format consume part of the device. For
that reason only `usb-audio` and the carefully minimized Bluetooth flavor are
8 MB candidates. The minimal Bluetooth flavor should not receive optional
packages unless the resulting image-size report still passes.

The combined and standard Bluetooth flavors are intended for devices with at
least 16 MB of flash. A profile can still select them on another target, but
the build must pass that target's own ImageBuilder limit.

The reference complete profiles for larger devices are:

- `x86-64-usb-bluetooth-audio-25.12.5`;
- `raspberry-pi-4-usb-bluetooth-audio-25.12.5`.

They use the complete Bluetooth and USB Audio stacks. The WDR4300 reference
profiles remain split between `usb-audio` and `minimal-usb-bluetooth` because
its 8 MB flash requires that choice.

## Reference flavors

### `usb-audio`

Uses OpenWrt's standard USB Audio and ALSA kernel packages. Bluetooth packages
are excluded. Dropbear, BusyBox udhcpd and umdns are included as standard services.

### `minimal-usb-bluetooth`

Uses AudioWRT's minimized Bluetooth runtime and generic USB Bluetooth kernel
drivers. It excludes USB Audio and umdns to fit constrained devices, while
retaining BusyBox udhcpd for provisioning. It retains `luci-mod-status`, `luci-mod-system` and
`luci-app-package-manager`, so the system can be inspected, reconfigured and
extended from LuCI.

No chipset-specific Bluetooth firmware is included by the flavor. A profile or
deployment may add a required firmware package for a particular dongle.

### `usb-bluetooth`

Uses the standard OpenWrt Bluetooth packages and kernel drivers. It keeps
Dropbear, BusyBox udhcpd and umdns and is intended for devices with more flash.

### `minimal-usb-bluetooth-audio`

Combines the minimized Bluetooth runtime with OpenWrt's standard USB Audio
stack. It keeps the minimal service policy and is intended for 16 MB devices.

### `usb-bluetooth-audio`

Combines the standard OpenWrt Bluetooth and USB Audio stacks. It keeps the
standard service policy and is intended for 16 MB devices or larger.

## Adding optional packages in a profile

Use a profile override when a particular image needs an optional service:

```yaml
packages_add:
  - dropbear
  - rtl8761b-firmware
packages_remove: []
```

Use `packages_remove` to make a standard base smaller for a known deployment:

```yaml
packages_add: []
packages_remove:
  - dropbear
  - umdns
```

The package must exist in the selected OpenWrt release or in the AudioWRT
package feed. Package names are validated during profile resolution, and the
final image is checked by ImageBuilder.
