AUDIOWRT_PROFILE ?= tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5
AUDIOWRT_PACKAGES_REF ?= main
PROVISIONING_IP ?= 192.168.77.1
export PROVISIONING_IP
OPENWRT_VERSION ?=
TARGET ?=
SUBTARGET ?=
ARCH ?=
JOBS ?=
VERBOSITY ?= normal
LOG_FILE ?=
CACHE_DIR ?=
PACKAGE ?=

.PHONY: help build packages package clean

help:
	@printf '%s\n' \
	  'AudioWRT build targets:' \
	  '' \
	  '  make build AUDIOWRT_PROFILE=<profile> [PROVISIONING_IP=192.168.77.1] [AUDIOWRT_PACKAGES_REF=main] [JOBS=N] [VERBOSITY=normal|verbose|debug] [LOG_FILE=logs/build.log] [CACHE_DIR=.cache/audiowrt]' \
	  '  make packages OPENWRT_VERSION=<version> TARGET=<target> SUBTARGET=<subtarget> ARCH=<arch> PACKAGE="<package-name ...>" [AUDIOWRT_PACKAGES_REF=main] [JOBS=N] [VERBOSITY=normal|verbose|debug] [CACHE_DIR=.cache/audiowrt]' \
	  '  make package ...  (alias of make packages)' \
	  '  make clean' \
	  '' \
	  'Reference device:' \
	  '  make build AUDIOWRT_PROFILE=tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5' \
	  '' \
	  'Package builds are selected only by OpenWrt version, target/subtarget and architecture.' \
	  '' \
	  'Build environment:' \
	  '  demonccc/openwrt-builder:latest (fixed by AudioWRT; not configurable)'

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
	@if [ -z "$(OPENWRT_VERSION)" ]; then echo 'ERROR: OPENWRT_VERSION is required.' >&2; exit 2; fi
	@if [ -z "$(TARGET)" ]; then echo 'ERROR: TARGET is required.' >&2; exit 2; fi
	@if [ -z "$(SUBTARGET)" ]; then echo 'ERROR: SUBTARGET is required.' >&2; exit 2; fi
	@if [ -z "$(ARCH)" ]; then echo 'ERROR: ARCH is required.' >&2; exit 2; fi
	@if [ -z "$(PACKAGE)" ]; then echo 'ERROR: PACKAGE must contain one or more AudioWRT package names.' >&2; exit 2; fi
	@AUDIOWRT_BUILD_MODE="packages" \
	 AUDIOWRT_PACKAGE="$(PACKAGE)" \
	 AUDIOWRT_PROFILE="package-context-$(OPENWRT_VERSION)" \
	 AUDIOWRT_PACKAGE_TARGET="$(TARGET)" \
	 AUDIOWRT_PACKAGE_SUBTARGET="$(SUBTARGET)" \
	 AUDIOWRT_PACKAGE_ARCH="$(ARCH)" \
	 AUDIOWRT_PACKAGES_REF="$(AUDIOWRT_PACKAGES_REF)" \
	 JOBS="$(JOBS)" \
	 VERBOSITY="$(VERBOSITY)" \
	 LOG_FILE="$(LOG_FILE)" \
	 CACHE_DIR="$(CACHE_DIR)" \
	 bash scripts/run-in-docker.sh

package: packages

clean:
	@rm -rf .work output
