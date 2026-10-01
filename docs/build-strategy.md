# AudioWRT build and branching strategy

## Branch model

AudioWRT uses two persistent branches:

- `main`: stable and releasable state.
- `testing`: integration and hardware-test state.

Development happens on temporary `feature/*` and `fix/*` branches. Normal development PRs target `testing`. Promotion from `testing` to `main` is explicit. Git tags are not required for ordinary firmware/profile changes; firmware identity comes from build provenance.

The same branch model applies to `demonccc/audiowrt-packages`.

## Separation of package and firmware builds

Package compilation and firmware composition are separate pipelines.

### Package pipeline

`make packages` uses the official OpenWrt SDK selected by an AudioWRT profile. It is the only pipeline that compiles AudioWRT package sources or selected upstream/OpenWrt sources.

Published package builds are incremental. `audiowrt-packages` publishes only changed packages plus explicitly declared rebuild dependents. GitHub Release assets are immutable binary storage. GitHub Pages exposes the current logical package repository metadata for the `stable` and `testing` channels.

### Firmware pipeline

`make build` does not compile AudioWRT packages. It uses:

1. the exact official OpenWrt ImageBuilder selected by the profile;
2. the profile's official OpenWrt packages;
3. published AudioWRT APKs resolved from the selected package channel.

The default package channel is `stable`. A test firmware can use `AUDIOWRT_PACKAGES_CHANNEL=testing`.

## Published repository layout

GitHub Pages publishes metadata at:

```text
/<channel>/<openwrt-version>/<target>/<subtarget>/repository.json
```

For example:

```text
/stable/25.12.5/ath79/generic/repository.json
/testing/25.12.5/ath79/generic/repository.json
```

The metadata maps each current package to an immutable GitHub Release asset and records its SHA256, source commit, source directory, version and release tag.

A package Release is storage for one incremental build. It is not an AudioWRT software release and does not imply semantic versioning.

## OpenWrt compatibility

A published repository is scoped to an exact OpenWrt version plus target/subtarget. Package metadata also records the OpenWrt package architecture.

A future maintenance release may be compatible with some existing userspace APKs, but reuse across OpenWrt versions must be an explicit compatibility decision. Kernel packages remain tied to the exact target/kernel ABI represented by the OpenWrt release repository.

## Firmware provenance

Each firmware records at least:

- AudioWRT commit;
- profile;
- exact OpenWrt version and target/subtarget;
- package channel;
- package repository revision;
- package repository metadata SHA256;
- package repository last update release;
- official ImageBuilder URL.

That provenance, rather than a Git tag, identifies the exact firmware composition.
