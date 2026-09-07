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

## Relationship to recent openwrt-builder changes

The recent `release-patched` host-tools fix does not require equivalent AudioWRT code. `openwrt-builder` needs special handling because `release-patched` can generate a custom ImageBuilder; AudioWRT compiles its packages with the official SDK and assembles firmware with the official ImageBuilder directly, so SDK host tools are never copied into a generated ImageBuilder.

The reusable Docker image remains environment-only. AudioWRT scripts come from the mounted AudioWRT checkout, so script-only changes do not require rebuilding the `openwrt-builder` image.
