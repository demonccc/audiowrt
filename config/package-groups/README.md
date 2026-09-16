# AudioWRT package groups

AudioWRT firmware composition is based on package groups, not flavors.

`common` is the mandatory AudioWRT baseline and is applied automatically to every profile. It is not selected explicitly.

Reusable base groups:

- `minimal`: shared constrained-device policy used by all `minimal-*` groups.

Selectable capability groups are:

- `minimal-usb-audio`
- `minimal-usb-bluetooth`
- `minimal-usb-audio-bluetooth`
- `usb-audio`
- `usb-bluetooth`
- `usb-audio-bluetooth`

Package groups may declare `include` entries to reuse another package group. Includes are resolved recursively before the current group's own `packages_add` / `packages_remove` entries are applied. Include cycles are rejected.

The three `minimal-*` groups include `minimal`, so shared minimal packages and removals are defined once instead of duplicated.

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

Runtime files and package-specific configuration do not belong in this repository. They must be owned by a package under `audiowrt-packages` (including metadata/configuration-only packages when appropriate).

## Hardware responsibility

AudioWRT does not try to infer or enforce USB-host capability during the build. A profile maintainer must verify that the target hardware can expose an audio path suitable for the selected package group, such as USB Audio or a USB Bluetooth adapter. OpenWrt device metadata and the hardware documentation should be checked before publishing or using a profile.
