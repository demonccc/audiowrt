# Build diagnostics

AudioWRT follows the diagnostic conventions used by `demonccc/openwrt-builder` where they apply to this repository.

## Verbosity

`VERBOSITY` controls OpenWrt and SDK `make` output:

```text
normal  -> default OpenWrt output
verbose -> V=s
debug   -> V=sc
```

Example:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5 \
  JOBS=1 \
  VERBOSITY=debug
```

For difficult failures, `JOBS=1` keeps command output ordered and `VERBOSITY=debug` exposes the maximum OpenWrt make diagnostics.

## Local log file

Local builds can tee the complete build output to a host file while keeping the same output in the terminal:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5 \
  JOBS=1 \
  VERBOSITY=debug \
  LOG_FILE=logs/wdr4300.log
```

`LOG_FILE` is resolved on the host before Docker starts, so it also captures Docker image pulls and container execution errors. Relative paths are resolved from the AudioWRT checkout.

The log must stay outside `.work/` and `output/` because those directories are recreated during a build. `*.log` is ignored by Git.

GitHub Actions intentionally does not expose a log-file input. The workflow is manual-only and the Actions job already retains the complete console log.

## Persistent local download cache

The current `openwrt-builder` supports an optional persistent cache for downloaded build inputs. AudioWRT now follows the same rule with `CACHE_DIR`:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5 \
  CACHE_DIR=.cache/audiowrt
```

The cache is disabled by default. When enabled, AudioWRT reuses:

- the exact-release OpenWrt SDK archive;
- the exact-release OpenWrt ImageBuilder archive;
- OpenWrt package/source downloads stored under the SDK `dl/` directory.

The build tree, SDK extraction, ImageBuilder extraction, target state and generated firmware are still recreated. The cache therefore reduces repeated downloads without turning previous compilation state into an implicit build input.

Archive cache entries are keyed by their resolved URL and are written through a temporary `.part` file before being atomically moved into place. OpenWrt still validates package/source archives using its normal declared hashes.

`CACHE_DIR` must live inside the AudioWRT checkout so the directory is visible through the Docker bind mount, and it must stay outside `.work/` and `output/`. The recommended location is:

```text
.cache/audiowrt
```

`.cache/` is ignored by Git. `make clean` intentionally leaves the cache intact.

For repeated troubleshooting runs, combine the cache with a local log and ordered debug output:

```sh
make build \
  PLATFORM=tplink_tl-wdr4300-v1 \
  OPENWRT_RELEASE=25.12.5 \
  CACHE_DIR=.cache/audiowrt \
  JOBS=1 \
  VERBOSITY=debug \
  LOG_FILE=logs/wdr4300.log
```

GitHub Actions intentionally does not set `CACHE_DIR`; runner builds remain clean and ephemeral.

## Relationship to recent openwrt-builder changes

The newest `release-patched` stabilization changes how `openwrt-builder` combines SDK host tools with the generated custom ImageBuilder: source compilation keeps the SDK host tools/toolchain coherent, while the generated ImageBuilder receives the host-tool tree from the official ImageBuilder matching the base release.

AudioWRT does not need equivalent host-tool replacement logic because it never generates a custom ImageBuilder. It compiles AudioWRT-owned packages with the official SDK and then runs the official ImageBuilder for the same exact release directly.

The persistent download-cache idea does apply to AudioWRT, because our build repeatedly downloads the same SDK, ImageBuilder and package source archives during local iteration. That behavior is implemented independently in the AudioWRT build wrapper rather than by invoking `openwrt-builder`'s profile/build CLI.

The reusable Docker image remains environment-only. AudioWRT scripts come from the mounted AudioWRT checkout, so script-only changes do not require rebuilding the `openwrt-builder` image.
