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
4. Run `python3 scripts/validate-profile-catalog.py` and
   `python3 tests/test-profile-catalog.py`. Contributors do not need to edit
   the build workflow: its dropdown is regenerated after merge.
5. Build the new profile and include the device revision, image result and basic
   USB Audio/network validation in the pull request.

Profiles are data only. Per-device shell scripts or duplicated package catalogs
are not accepted; a reusable package belongs in `audiowrt-packages`, and shared
package policy belongs in a flavor.

## Validation and repository setup

The `Validate profile catalog` check runs on every pull request and merge group.
It validates every entry in `profiles/`, permitting only regular `.yaml` profile
files and `README.md`. Wrong extensions, subdirectories and symlinks fail.
The resolver checks the filename, all eight mandatory fields, schema version,
status, GitHub username format, identifiers, duplicate/unknown keys and package
list conflicts. This is schema validation; it does not certify real hardware,
GitHub account existence or upstream device availability.

Configure the main branch ruleset to require pull requests and the
`Validate profile catalog` status check, with the branch up to date before merge.
Without this repository-side setting, failed CI does not prevent a merge.
Protect the validator and workflows with maintainer review so a profile PR cannot
silently weaken its own checks. These settings are not activated by merging YAML.

`Sync build profile options` runs after profile-related changes land on `main`,
validates the catalog again and commits only the generated build workflow.
It handles additions, removals, renames and removal of the current default.
It can also be rerun manually on main; no diff produces no commit. Concurrent
updates are rejected by a normal fast-forward push; rerun after such a conflict.

Before enabling automatic publication, configure repository secret
`PROFILE_SYNC_TOKEN`: a dedicated credential scoped to this repository with
Contents and Workflows write permissions. Its actor must be permitted by the
repository rules to publish the generated workflow on main. Do not disable
protection for contributors. The ordinary GITHUB_TOKEN cannot supply the required
workflow-editing permission. The sync job fails explicitly if a change needs
publication and this credential is missing. Secrets are used only on main,
never in pull-request validation.

GitHub references:
- [Required status checks](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [Workflow file write permissions](https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents)
