AUDIOWRT_PROFILE ?= tplink-tl-wdr4300-v1-minimal-25.12.5
AUDIOWRT_PACKAGES_REF ?= main
JOBS ?=
VERBOSITY ?= normal
LOG_FILE ?=
CACHE_DIR ?=

.PHONY: help build clean

help:
	@printf '%s\n' \
	  'AudioWRT build targets:' \
	  '' \
	  '  make build AUDIOWRT_PROFILE=<device-flavor-version> [AUDIOWRT_PACKAGES_REF=main] [JOBS=N] [VERBOSITY=normal|verbose|debug] [LOG_FILE=logs/build.log] [CACHE_DIR=.cache/audiowrt]' \
	  '  make clean' \
	  '' \
	  'Reference device:' \
	  '  make build AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-25.12.5' \
	  '' \
	  'Diagnostics:' \
	  '  JOBS=1 VERBOSITY=debug LOG_FILE=logs/wdr4300.log CACHE_DIR=.cache/audiowrt' \
	  '  LOG_FILE is for local builds only and must stay outside .work/ and output/.' \
	  '  CACHE_DIR is optional, local-only, and reuses SDK, ImageBuilder and OpenWrt source downloads.' \
	  '' \
	  'Build environment:' \
	  '  demonccc/openwrt-builder:latest (fixed by AudioWRT; not configurable)' \
	  '' \
	  'The selected profile pins its OpenWrt release or explicitly opts into snapshot.'

build:
	@if [ -z "$(AUDIOWRT_PROFILE)" ]; then echo 'ERROR: AUDIOWRT_PROFILE is required.' >&2; exit 2; fi
	@AUDIOWRT_PROFILE="$(AUDIOWRT_PROFILE)" \
	 AUDIOWRT_PACKAGES_REF="$(AUDIOWRT_PACKAGES_REF)" \
	 JOBS="$(JOBS)" \
	 VERBOSITY="$(VERBOSITY)" \
	 LOG_FILE="$(LOG_FILE)" \
	 CACHE_DIR="$(CACHE_DIR)" \
	 bash scripts/run-in-docker.sh

clean:
	@rm -rf .work output
