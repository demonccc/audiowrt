PLATFORM ?=
OPENWRT_REF ?= stable
AUDIOWRT_PACKAGES_REF ?= main
JOBS ?=

.PHONY: help build clean

help:
	@printf '%s\n' \
	  'AudioWRT build targets:' \
	  '' \
	  '  make build PLATFORM=<openwrt-profile> [OPENWRT_REF=stable] [AUDIOWRT_PACKAGES_REF=main] [JOBS=N]' \
	  '  make clean' \
	  '' \
	  'Examples:' \
	  '  make build PLATFORM=glinet_gl-mt6000' \
	  '  make build PLATFORM=glinet_gl-mt6000 OPENWRT_REF=openwrt-25.12 JOBS=8' \
	  '  make build PLATFORM=glinet_gl-mt6000 AUDIOWRT_PACKAGES_REF=feat/mvp-runtime'

build:
	@if [ -z "$(PLATFORM)" ]; then \
		echo 'ERROR: PLATFORM is required.' >&2; \
		echo 'Example: make build PLATFORM=glinet_gl-mt6000' >&2; \
		exit 2; \
	fi
	@PLATFORM="$(PLATFORM)" OPENWRT_REF="$(OPENWRT_REF)" AUDIOWRT_PACKAGES_REF="$(AUDIOWRT_PACKAGES_REF)" JOBS="$(JOBS)" bash scripts/build.sh

clean:
	@rm -rf .work output
