PLATFORM ?=
OPENWRT_RELEASE ?= 25.12.5
AUDIOWRT_PACKAGES_REF ?= main
FEATURES ?=
JOBS ?=
VERBOSITY ?= normal
LOG_FILE ?=
BUILDER_IMAGE ?= demonccc/openwrt-builder:latest

.PHONY: help build clean

help:
	@printf '%s\n' \
	  'AudioWRT build targets:' \
	  '' \
	  '  make build PLATFORM=<openwrt-profile> [OPENWRT_RELEASE=25.12.5] [AUDIOWRT_PACKAGES_REF=main] [FEATURES="mpd airplay spotify bluetooth"] [JOBS=N] [VERBOSITY=normal|verbose|debug] [LOG_FILE=logs/build.log]' \
	  '  make clean' \
	  '' \
	  'Reference device:' \
	  '  make build PLATFORM=tplink_tl-wdr4300-v1 OPENWRT_RELEASE=25.12.5' \
	  '' \
	  'Diagnostics:' \
	  '  JOBS=1 VERBOSITY=debug LOG_FILE=logs/wdr4300.log' \
	  '  LOG_FILE is for local builds only and must stay outside .work/ and output/.' \
	  '' \
	  'Build environment:' \
	  '  BUILDER_IMAGE=demonccc/openwrt-builder:latest' \
	  '' \
	  'AudioWRT accepts exact final OpenWrt releases only. openwrt-25.12, main and snapshots are intentionally rejected.'

build:
	@if [ -z "$(PLATFORM)" ]; then echo 'ERROR: PLATFORM is required.' >&2; echo 'Example: make build PLATFORM=tplink_tl-wdr4300-v1 OPENWRT_RELEASE=25.12.5' >&2; exit 2; fi
	@PLATFORM="$(PLATFORM)" \
	 OPENWRT_RELEASE="$(OPENWRT_RELEASE)" \
	 AUDIOWRT_PACKAGES_REF="$(AUDIOWRT_PACKAGES_REF)" \
	 FEATURES="$(FEATURES)" \
	 JOBS="$(JOBS)" \
	 VERBOSITY="$(VERBOSITY)" \
	 LOG_FILE="$(LOG_FILE)" \
	 BUILDER_IMAGE="$(BUILDER_IMAGE)" \
	 bash scripts/run-in-docker.sh

clean:
	@rm -rf .work output
