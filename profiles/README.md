# AudioWRT device profiles

Each YAML file combines one OpenWrt device profile with one AudioWRT flavor.
The file name without `.yaml` is the value passed as `AUDIOWRT_PROFILE`.

```yaml
schema_version: 1
status: community
maintainer_github: github-user
openwrt_profile: vendor_example-device
target: ath79
subtarget: generic
packages_add:
  - device-specific-package
packages_remove: []
```

The file name is the normalized
`<device>-<minimal|standard|full>-<X.Y.Z|snapshot>` identifier. Device, flavor,
OpenWrt source and version are derived from it and deliberately are not
repeated inside the file. Flavor package sets live under `config/flavors/`;
use `packages_add` and `packages_remove` only for genuine device exceptions.

Status values are:

- `reference`: primary AudioWRT development device;
- `tested`: built and verified on the named hardware;
- `candidate`: maintained by AudioWRT but awaiting hardware validation;
- `community`: contributed mapping awaiting broader validation.

`maintainer_github` is mandatory and contains one GitHub username without the
leading `@`. It identifies the person to mention when build or device-specific
issues are reported.

## Contributing a profile

1. Confirm that the exact `openwrt_profile`, `target` and `subtarget` exist in
   the OpenWrt release used by AudioWRT.
2. Confirm that the device has USB host support; AudioWRT rejects targets where
   OpenWrt metadata cannot prove it.
3. Add one YAML file per device/flavor/OpenWrt-version combination. The ID and
   filename must end in the exact release (`-25.12.5`) or `-snapshot`. Retain
   OpenWrt's exact underscore-containing device profile ID.
4. Run `python3 scripts/sync-profile-workflow.py` to regenerate the GitHub
   Actions dropdown, then run `bash tests/test-flavors-and-profiles.sh`.
5. Build the new profile and include the device revision, image result and basic
   USB Audio/network validation in the pull request.

Profiles are data only. Per-device shell scripts or duplicated package catalogs
are not accepted; a reusable package belongs in `audiowrt-packages`, and shared
package policy belongs in a flavor.
