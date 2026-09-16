# AudioWRT package groups

AudioWRT firmware composition is based on package groups, not flavors.

`common` is the mandatory AudioWRT baseline and is applied automatically to every profile. It is not selected explicitly.

Selectable package groups are:

- `minimal-usb-audio`
- `minimal-usb-bluetooth`
- `minimal-usb-audio-bluetooth`
- `usb-audio`
- `usb-bluetooth`
- `usb-audio-bluetooth`

A profile selects the package group or groups it needs through `package_groups`. Package groups define package selection only. Device-specific exceptions belong in the profile's `packages_add` / `packages_remove` overrides.

Example:

```yaml
package_groups:
  - minimal-usb-bluetooth
```

`common` is applied first, selected package groups are applied in the order listed, and profile overrides are applied last.

Runtime files and package-specific configuration do not belong in this repository. They must be owned by a package under `audiowrt-packages` (including metadata/configuration-only packages when appropriate).

## Hardware responsibility

AudioWRT does not try to infer or enforce USB-host capability during the build. A profile maintainer must verify that the target hardware can expose an audio path suitable for the selected package group, such as USB Audio or a USB Bluetooth adapter. OpenWrt device metadata and the hardware documentation should be checked before publishing or using a profile.
