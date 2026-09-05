PLATFORM ?=
OPENWRT_REF ?= stable
JOBS ?=

.PHONY: help build clean

help:
	@printf '%s\n' \
	  'AudioWRT build targets:' \
	  '' \
	  '  make build PLATFORM=<openwrt-profile> [OPENWRT_REF=stable] [JOBS=N]' \
	  '  make clean' \
	  '' \
	  'Examples:' \
	  '  make build PLATFORM=glinet_gl-mt6000' \
	  '  make build PLATFORM=glinet_gl-mt6000 OPENWRT_REF=openwrt-25.12 JOBS=8'

build:
	@if [ -z "$(PLATFORM)" ]; then \
		echo 'ERROR: PLATFORM is required.' >&2; \
		echo 'Example: make build PLATFORM=glinet_gl-mt6000' >&2; \
		exit 2; \
	fi
	@PLATFORM="$(PLATFORM)" OPENWRT_REF="$(OPENWRT_REF)" JOBS="$(JOBS)" bash scripts/build.sh

clean:
	@rm -rf .work output
