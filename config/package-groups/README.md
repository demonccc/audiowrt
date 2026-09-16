# AudioWRT package groups

AudioWRT firmware composition is based on ordered package groups, not flavors.

`common` is applied automatically to every profile. A device profile then selects zero or more additional groups through `package_groups`.

Groups are overlays and are applied in the order listed by the profile. When a later group adds a package that an earlier group removed, it is added. When a later group removes a package that an earlier group added, it is removed. Device-level `packages_add` and `packages_remove` overrides are applied last.

Example:

```yaml
package_groups:
  - usb-bluetooth
  - minimal
  - usb-audio
```

This produces the common AudioWRT baseline, then Bluetooth, then the minimal replacements/policy, then re-adds the normal USB Audio stack. This replaces the old dedicated combined flavor definitions.

Current groups:

- `common`: mandatory AudioWRT baseline and global exclusions. It is automatic and must not be listed explicitly.
- `minimal`: constrained-device replacements and removals.
- `usb-audio`: USB Audio capability.
- `usb-bluetooth`: USB Bluetooth capability.

A package group owns package selection only. Runtime files and package-specific configuration belong in packages under `audiowrt-packages`. For example, system branding is installed by the `audiowrt-branding` metadata package rather than injected from this repository.
