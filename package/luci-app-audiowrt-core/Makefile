include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-audiowrt-core
PKG_RELEASE:=2
PKG_LICENSE:=Apache-2.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-audiowrt-core
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=AudioWRT distribution management interface
  DEPENDS:=+luci-base +rpcd-mod-file +luci-app-audiowrt +audiowrt-core +audiowrt-provisioning +audiowrt-storage
endef

define Package/luci-app-audiowrt-core/description
 AudioWRT-only LuCI pages for network provisioning, guided extension storage and appliance system state.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-audiowrt-core/install
	$(INSTALL_DIR) $(1)/www
	$(CP) ./htdocs/* $(1)/www/
	$(INSTALL_DIR) $(1)/
	$(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-audiowrt-core))
