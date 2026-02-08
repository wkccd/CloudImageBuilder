TOPDIR:=${CURDIR}
LC_ALL:=C
LANG:=C
export TOPDIR LC_ALL LANG
export OPENWRT_VERBOSE=s
all: help

export ORIG_PATH:=$(if $(ORIG_PATH),$(ORIG_PATH),$(PATH))
export PATH:=$(TOPDIR)/staging_dir/host/bin:$(PATH)

ifneq ($(OPENWRT_BUILD),1)
  override OPENWRT_BUILD=1
  export OPENWRT_BUILD
endif

include rules.mk
include $(INCLUDE_DIR)/debug.mk
include $(INCLUDE_DIR)/depends.mk
include $(INCLUDE_DIR)/rootfs.mk
include $(INCLUDE_DIR)/version.mk
export REVISION
export SOURCE_DATE_EPOCH

# -------------------------------
# Keys & Packages
# -------------------------------
BUILD_KEY_APK_SEC=$(TOPDIR)/keys/local-private-key.pem
BUILD_KEY_APK_PUB=$(TOPDIR)/keys/local-public-key.pem
export PACKAGE_DIR:=$(TOPDIR)/packages
LISTS_DIR:=$(subst $(space),/,$(patsubst %,..,$(subst /,$(space),$(TARGET_DIR))))$(DL_DIR)
export PACKAGE_DIR_ALL:=$(TOPDIR)/packages

# APK only, do not use opkg
export APK_KEYS:=$(TOPDIR)/keys
APK:=$(call apk,$(TARGET_DIR)) \
	--repositories-file $(TOPDIR)/repositories \
	--repository $(PACKAGE_DIR)/packages.adb \
	$(if $(CONFIG_SIGNATURE_CHECK),,--allow-untrusted) \
	--cache-dir $(DL_DIR)

# -------------------------------
# _check_keys target
# -------------------------------
_check_keys: FORCE
ifneq ($(CONFIG_SIGNATURE_CHECK),)
ifeq ("$(CONFIG_USE_APK)","")
	# Only APK is supported in this Makefile
	@echo "Non-APK opkg mode not supported in this container"
	@exit 1
else
	@if [ ! -s $(BUILD_KEY_APK_SEC) -o ! -s $(BUILD_KEY_APK_PUB) ]; then \
		echo Generate local APK signing keys... >&2; \
		$(STAGING_DIR_HOST)/bin/openssl ecparam -name prime256v1 -genkey -noout -out $(BUILD_KEY_APK_SEC); \
		sed -i '1s/^/untrusted comment: Local build key\n/' $(BUILD_KEY_APK_SEC); \
		$(STAGING_DIR_HOST)/bin/openssl ec -in $(BUILD_KEY_APK_SEC) -pubout > $(BUILD_KEY_APK_PUB); \
		sed -i '1s/^/untrusted comment: Local build key\n/' $(BUILD_KEY_APK_PUB); \
	fi
endif
endif

# -------------------------------
# Build targets
# -------------------------------
package_index: FORCE
	@echo "Building package index..."
	(cd $(PACKAGE_DIR); $(APK) mkndx \
		$(if $(CONFIG_SIGNATURE_CHECK), --keys-dir $(APK_KEYS) --sign $(BUILD_KEY_APK_SEC)) \
		--allow-untrusted --output packages.adb *.apk) >/dev/null 2>/dev/null || true

package_reload: FORCE
	$(APK) add --arch $(ARCH_PACKAGES) --initdb
	if [ -d "$(PACKAGE_DIR)" ] && ( \
			[ ! -f "$(PACKAGE_DIR)/packages.adb" ] || \
			[ "`find $(PACKAGE_DIR) -cnewer $(PACKAGE_DIR)/packages.adb`" ] ); then \
		echo "Package list missing or not up-to-date, generating it." >&2 ;\
		$(MAKE) package_index; \
	else \
		mkdir -p $(TARGET_DIR)/tmp; \
	fi

package_install: FORCE
	@echo
	@echo Installing packages...
	$(eval BUILD_PACKAGES:=$(call FormatPackages,$(BUILD_PACKAGES)))
	$(APK) add --arch $(ARCH_PACKAGES) --no-scripts $(BUILD_PACKAGES)

# -------------------------------
# Rootfs preparation
# -------------------------------
prepare_rootfs: FORCE
	@echo
	@echo Finalizing root filesystem...
	$(CP) $(TARGET_DIR) $(TARGET_DIR_ORIG)
	$(if $(CONFIG_SIGNATURE_CHECK), \
		$(if $(ADD_LOCAL_KEY), \
			mkdir -p $(TARGET_DIR)/etc/apk/keys/; \
			cp $(BUILD_KEY_APK_PUB) $(TARGET_DIR)/etc/apk/keys/; \
		) \
	)
	$(call prepare_rootfs,$(TARGET_DIR),$(USER_FILES),$(DISABLED_SERVICES))

# -------------------------------
# Image build
# -------------------------------
_call_image: staging_dir/host/.prereq-build
	echo 'Building images for $(BOARD)$(if $($(USER_PROFILE)_NAME), - $($(USER_PROFILE)_NAME))'
	echo 'Packages: $(BUILD_PACKAGES)'
	echo
	rm -rf $(TARGET_DIR) $(TARGET_DIR_ORIG)
	mkdir -p $(TARGET_DIR) $(BIN_DIR) $(TMP_DIR) $(DL_DIR)
	$(MAKE) package_reload
	$(MAKE) package_install
	$(MAKE) -s prepare_rootfs
	$(MAKE) -s build_image
	$(MAKE) -s json_overview_image_info
	$(MAKE) -s checksum

image: FORCE
	$(MAKE) -s _check_keys
	(unset PROFILE FILES PACKAGES MAKEFLAGS; \
	$(MAKE) -s _call_image \
		$(if $(PROFILE),USER_PROFILE="$(PROFILE_FILTER)") \
		$(if $(FILES),USER_FILES="$(FILES)") \
		$(if $(PACKAGES),USER_PACKAGES="$(PACKAGES)") \
		$(if $(BIN_DIR),BIN_DIR="$(BIN_DIR)") \
		$(if $(DISABLED_SERVICES),DISABLED_SERVICES="$(DISABLED_SERVICES)") \
		$(if $(ROOTFS_PARTSIZE),CONFIG_TARGET_ROOTFS_PARTSIZE="$(ROOTFS_PARTSIZE)"))
