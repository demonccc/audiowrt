PLATFORM ?=
OPENWRT_REF ?= stable
AUDIOWRT_PACKAGES_REF ?= main
FEATURES ?=
JOBS ?=

.PHONY: help build clean

help:
	@printf '%s\n' \
	  'AudioWRT build targets:' \
	  '' \
	  '  make build PLATFORM=<openwrt-profile> [OPENWRT_REF=stable] [AUDIOWRT_PACKAGES_REF=main] [FEATURES="mpd airplay"] [JOBS=N]' \
	  '  make clean' \
	  '' \
	  'Reference device:' \
	  '  make build PLATFORM=tplink_tl-wdr4300-v1' \
	  '' \
	  'Optional engines preinstalled in the firmware:' \
	  '  make build PLATFORM=tplink_tl-wdr4300-v1 FEATURES="mpd airplay"' \
	  '' \
	  'For constrained devices, leave FEATURES empty and install engines later from the AudioWRT Extensions UI.'

build:
	@if [ -z "$(PLATFORM)" ]; then \
		echo 'ERROR: PLATFORM is required.' >&2; \
		echo 'Example: make build PLATFORM=tplink_tl-wdr4300-v1' >&2; \
		exit 2; \
	fi
	@PLATFORM="$(PLATFORM)" OPENWRT_REF="$(OPENWRT_REF)" AUDIOWRT_PACKAGES_REF="$(AUDIOWRT_PACKAGES_REF)" FEATURES="$(FEATURES)" JOBS="$(JOBS)" bash scripts/build.sh

clean:
	@rm -rf .work output
