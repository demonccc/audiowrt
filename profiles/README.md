# AudioWRT device profiles

Each YAML file binds an OpenWrt device profile to an ordered set of AudioWRT package groups. The file name without `.yaml` is the value passed as `AUDIOWRT_PROFILE`.

```yaml
schema_version: 1
status: community
maintainer_github: github-user
openwrt_profile: vendor_example-device
target: ath79
subtarget: generic
squashfs_block_size: default
package_groups:
  - usb-audio
packages_add:
  - device-specific-package
packages_remove: []
```

The profile ID must end in the OpenWrt version (`-25.12.5`) or `-snapshot`. Package capabilities are not inferred from the file name; `package_groups` is the canonical composition.

`common` is applied automatically to every profile and must not be listed. Package groups may include reusable groups internally. In particular, every `minimal-*` capability group includes the shared `minimal` group, so constrained-device policy is maintained in one place.

For example, a constrained Bluetooth image uses:

```yaml
package_groups:
  - minimal-usb-bluetooth
```

A constrained USB Audio image uses:

```yaml
package_groups:
  - minimal-usb-audio
```

Shared composition belongs in `config/package-groups/`. Runtime files and package-specific configuration belong in packages under `audiowrt-packages`; device profiles remain data-only.

`squashfs_block_size` is optional. Omit it or set it to `default` to preserve the OpenWrt target configuration. Set it to `256`, `512` or `1024` to override the target's block size for that profile.

Status values are:

- `reference`: primary AudioWRT development device;
- `tested`: built and verified on the named hardware;
- `candidate`: maintained by AudioWRT but awaiting hardware validation;
- `community`: contributed mapping awaiting broader validation.

`maintainer_github` is mandatory and contains one GitHub username without the leading `@`.

## Contributing a profile

1. Confirm that the exact `openwrt_profile`, `target` and `subtarget` exist in the selected OpenWrt release.
2. Confirm that the target hardware provides the physical audio path required by the selected package group. AudioWRT does not reject a build automatically when USB-host capability cannot be inferred.
3. Select the required `package_groups`.
4. Use `packages_add` / `packages_remove` only for genuine device-specific exceptions.
5. Run `python3 scripts/validate-profile-catalog.py` and `python3 tests/test-profile-catalog.py`.
6. Build the new profile and include the device revision and basic runtime validation in the pull request.

Profiles are data only. Per-device shell scripts, duplicated package catalogs, and rootfs configuration files are not accepted here.
