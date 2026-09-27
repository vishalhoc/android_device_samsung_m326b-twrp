# SM-M326B / Samsung Galaxy M32 5G
# Platform: MT6853 (Dimensity 720)
# Codename: a32x (verified: ro.product.device = a32x on M326B)
# Board: k6853v1_64_titan
# Android 13 / One UI 5.1
# TWRP 3.7.0_12 (twrp-12.1 base)

$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)

# Device identification
PRODUCT_DEVICE       := a32x
PRODUCT_NAME         := twrp_a32x
PRODUCT_BRAND        := samsung
PRODUCT_MODEL        := SM-M326B
PRODUCT_MANUFACTURER := samsung

PRODUCT_GMS_CLIENTID_BASE := android-samsung

# API level — TWRP 12.1 supports up to SDK 32; device ships Android 13 (33)
# but TWRP doesn't care about this distinction functionally
PRODUCT_SHIPPING_API_LEVEL := 32

# Recovery-specific files
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt6853.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.mt6853.rc \
    $(LOCAL_PATH)/recovery/root/init.recovery.samsung.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.samsung.rc \
    $(LOCAL_PATH)/recovery/root/system/bin/multidisabler:$(TARGET_COPY_OUT_RECOVERY)/root/system/bin/multidisabler \
    $(LOCAL_PATH)/recovery/root/system/etc/recovery.fstab:$(TARGET_COPY_OUT_RECOVERY)/root/system/etc/recovery.fstab \
    $(LOCAL_PATH)/recovery/root/system/etc/twrp.flags:$(TARGET_COPY_OUT_RECOVERY)/root/system/etc/twrp.flags

# TWRP Soong variable injection — REQUIRED for getMakeVars(ctx, "VAR") in
# bootable/recovery/**/*.go (libguitwrp_defaults.go etc.) via VendorConfig("twrpVarsPlugin")
# Missing TW_THEME causes os.Exit(-1) during soong_build.
SOONG_CONFIG_NAMESPACES += twrpVarsPlugin
SOONG_CONFIG_twrpVarsPlugin_VARIABLES := \
    AB_OTA_UPDATER \
    BOARD_HAS_FLIPPED_SCREEN \
    DEVICE_RESOLUTION \
    TARGET_CUSTOM_KERNEL_HEADERS \
    TARGET_PREBUILT_KERNEL \
    TARGET_RECOVERY_FORCE_PIXEL_FORMAT \
    TARGET_RECOVERY_PIXEL_FORMAT \
    TARGET_SCREEN_HEIGHT \
    TARGET_SCREEN_WIDTH \
    TWRP_CUSTOM_KEYBOARD \
    TW_CUSTOM_THEME \
    TW_EXTRA_LANGUAGES \
    TW_HAPTICS_TSPDRV \
    TW_INCLUDE_JPEG \
    TW_ROTATION \
    TW_STATUS_ICONS_ALIGN \
    TW_SUPPORT_INPUT_AIDL_HAPTICS \
    TW_TARGET_USES_QCOM_BSP \
    TW_THEME

# Values for our M326B device
SOONG_CONFIG_twrpVarsPlugin_TW_THEME             := portrait_hdpi
SOONG_CONFIG_twrpVarsPlugin_TARGET_SCREEN_WIDTH  := 1080
SOONG_CONFIG_twrpVarsPlugin_TARGET_SCREEN_HEIGHT := 2408
SOONG_CONFIG_twrpVarsPlugin_TW_EXTRA_LANGUAGES   := true
SOONG_CONFIG_twrpVarsPlugin_TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888

