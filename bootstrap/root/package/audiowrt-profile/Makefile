include $(TOPDIR)/rules.mk

PKG_NAME:=audiowrt-profile
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/audiowrt-profile
  SECTION:=sound
  CATEGORY:=Sound
  TITLE:=AudioWRT default distribution profile
  DEPENDS:=+audiowrt-core +audiowrt-usb-audio +luci-app-audiowrt +wpad-basic-mbedtls +dnsmasq +uhttpd +umdns
endef

define Package/audiowrt-profile/description
 Default AudioWRT package profile for the initial audio appliance firmware.
endef

define Package/audiowrt-profile/install
	true
endef

$(eval $(call BuildPackage,audiowrt-profile))
