AUDIOWRT_PROFILE ?= tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5
AUDIOWRT_PACKAGES_REF ?= main
JOBS ?=
VERBOSITY ?= normal
LOG_FILE ?=
CACHE_DIR ?=
PACKAGE ?= all

.PHONY: help build packages package clean

help:
	@printf '%s\n' \
	  'AudioWRT build targets:' \
	  '' \
	  '  make build AUDIOWRT_PROFILE=<profile> [AUDIOWRT_PACKAGES_REF=main] [JOBS=N] [VERBOSITY=normal|verbose|debug] [LOG_FILE=logs/build.log] [CACHE_DIR=.cache/audiowrt]' \
	  '  make packages AUDIOWRT_PROFILE=<profile> PACKAGE=<all|package-name> [AUDIOWRT_PACKAGES_REF=main] [JOBS=N] [VERBOSITY=normal|verbose|debug] [CACHE_DIR=.cache/audiowrt]' \
	  '  make package ...  (alias of make packages)' \
	  '  make clean' \
	  '' \
	  'Reference device:' \
	  '  make build AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5' \
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
	@AUDIOWRT_BUILD_MODE="firmware" \
	 AUDIOWRT_PROFILE="$(AUDIOWRT_PROFILE)" \
	 AUDIOWRT_PACKAGES_REF="$(AUDIOWRT_PACKAGES_REF)" \
	 JOBS="$(JOBS)" \
	 VERBOSITY="$(VERBOSITY)" \
	 LOG_FILE="$(LOG_FILE)" \
	 CACHE_DIR="$(CACHE_DIR)" \
	 bash scripts/run-in-docker.sh

packages:
	@if [ -z "$(AUDIOWRT_PROFILE)" ]; then echo 'ERROR: AUDIOWRT_PROFILE is required.' >&2; exit 2; fi
	@if [ -z "$(PACKAGE)" ]; then echo 'ERROR: PACKAGE must be all or an AudioWRT package name.' >&2; exit 2; fi
	@AUDIOWRT_BUILD_MODE="packages" \
	 AUDIOWRT_PACKAGE="$(PACKAGE)" \
	 AUDIOWRT_PROFILE="$(AUDIOWRT_PROFILE)" \
	 AUDIOWRT_PACKAGES_REF="$(AUDIOWRT_PACKAGES_REF)" \
	 JOBS="$(JOBS)" \
	 VERBOSITY="$(VERBOSITY)" \
	 LOG_FILE="$(LOG_FILE)" \
	 CACHE_DIR="$(CACHE_DIR)" \
	 bash scripts/run-in-docker.sh

package: packages

clean:
	@rm -rf .work output
