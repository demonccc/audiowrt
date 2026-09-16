# AudioWRT flavors

AudioWRT flavors are declared as composable YAML files. A file may include one or more other flavor files and then add or remove packages on top of the inherited package policy.

Each file has this shape:

```yaml
schema_version: 1
include:
  - common
packages_add:
  - example-package
packages_remove:
  - unwanted-package
```

The resolver processes includes recursively, deduplicates repeated inherited directives, and then applies the current file's `packages_add` and `packages_remove` entries as explicit overrides.

## Conflict rule

Includes do **not** use "last include wins" semantics.

If one inherited flavor adds a package and another inherited flavor removes the same package, resolution fails unless the child flavor explicitly decides the result by listing that package in its own `packages_add` or `packages_remove` section.

This makes combined flavors self-documenting and prevents include order from silently changing the firmware composition.

Include cycles are also rejected.

## Shared fragments

`common.yaml` and `minimal.yaml` are reusable fragments and are not selectable device flavors.

### `common`

Contains policy that applies to every AudioWRT image. This includes the core AudioWRT packages and global exclusions such as the stock `busybox`, router services, and `dnsmasq`. Provisioning DHCP is provided by `audiowrt-udhcpd`.

### `minimal`

Includes `common` and contains policy shared by every constrained/minimal image, including minimal runtime replacements and removal of optional OpenWrt administration/network packages.

## Selectable flavors

The selectable flavor files are:

- `minimal-usb-audio`
- `minimal-usb-bluetooth`
- `minimal-usb-audio-bluetooth`
- `usb-audio`
- `usb-bluetooth`
- `usb-audio-bluetooth`

The two combined flavors are built by composition:

```text
minimal-usb-audio-bluetooth
├── minimal-usb-audio
└── minimal-usb-bluetooth

usb-audio-bluetooth
├── usb-audio
└── usb-bluetooth
```

Both minimal capability flavors inherit `common` and `minimal`. The non-minimal USB capability flavors inherit `common` directly.

## Device profiles

A device profile selects a flavor through its profile ID and may still use `packages_add` and `packages_remove` for genuine device-specific overrides. Profile overrides are applied after the complete flavor include graph has been resolved.

For example:

```yaml
packages_add:
  - rtl8761b-firmware
packages_remove: []
```

Shared package policy must live in `config/flavors/*.yaml`, not be duplicated into device profiles.

For compatibility, existing profile IDs using the former `usb-bluetooth-audio` and `minimal-usb-bluetooth-audio` naming are accepted by the resolver and mapped to the canonical `usb-audio-bluetooth` and `minimal-usb-audio-bluetooth` flavors.
