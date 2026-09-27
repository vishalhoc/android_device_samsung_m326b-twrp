DEVICE_PATH := device/samsung/a32x

TARGET_SUPPORTS_64_BIT_APPS := true
ALLOW_MISSING_DEPENDENCIES := true

# Build broken flags — confirmed required for twrp-12.1 on a32x/m326b
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BUILD_BROKEN_ARTIFACT_PATH_REQUIREMENTS := true

# Disable all sanitizers — runtime libs (libclang_rt.*) are only in Google's
# clang prebuilt, not in system clang 21. TWRP recovery doesn't need them.
# Note: use empty value, not 'never' — soong doesn't recognize 'never' as global option
SANITIZE_HOST :=
SANITIZE_TARGET :=

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a55

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv7-a-neon
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a55

# APEX
DEXPREOPT_GENERATE_APEX_IMAGE := true

# Bootloader
# Board name confirmed via ro.product.board = a32x, platform = mt6853
TARGET_BOOTLOADER_BOARD_NAME := k6853v1_64_titan
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true
TARGET_USES_UEFI := true
TARGET_USES_64_BIT_BINDER := true

# Display
TARGET_SCREEN_DENSITY := 300

# Kernel — PREBUILT from M326B stock boot.img (NOT A326B kernel)
# M326B kernel: 17,961,251 bytes gzip-compressed (Image.gz), magic: 1F 8B 08 00
# A326B kernel: 18,008,668 bytes — DIFFERENT, do not use for M326B
TARGET_FORCE_PREBUILT_KERNEL := true
TARGET_PREBUILT_KERNEL  := $(DEVICE_PATH)/prebuilt/kernel
TARGET_PREBUILT_DTB     := $(DEVICE_PATH)/prebuilt/dtb.img
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img

# Boot image header v2 parameters
# All values confirmed by binary parsing of M326B stock boot.img
BOARD_BOOTIMG_HEADER_VERSION := 2
BOARD_KERNEL_BASE         := 0x40078000
BOARD_KERNEL_PAGESIZE     := 2048
BOARD_RAMDISK_OFFSET      := 0x07c08000
BOARD_KERNEL_TAGS_OFFSET  := 0x0bc08000
BOARD_KERNEL_IMAGE_NAME   := Image.gz   # gzip-compressed, confirmed from kernel magic 1F 8B

# mkbootimg arguments
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb $(TARGET_PREBUILT_DTB)

# DTB is supplied separately via --dtb (v2 format), not embedded via INCLUDE_DTB
BOARD_INCLUDE_DTB_IN_BOOTIMG :=

# DTBO (separate partition, index 5 confirmed: androidboot.dtbo_idx=5)
BOARD_KERNEL_SEPARATED_DTBO := true

# Kernel cmdline
# From /proc/cmdline on live M326B:
#   bootopt=64S3,32N2,64N2 loop.max_part=7
# androidboot.selinux=permissive required for TWRP to operate
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 loop.max_part=7 androidboot.selinux=permissive

# Partitions — ALL VALUES VERIFIED FROM LIVE M326B DEVICE
# blockdev --getsize64 results, do NOT substitute A326B values here
BOARD_FLASH_BLOCK_SIZE               := 131072    # 2048 (pagesize) * 64

# M326B boot = 32 MiB = 33,554,432 bytes (A326B has 40 MiB — DIFFERENT)
BOARD_BOOTIMAGE_PARTITION_SIZE       := 33554432

# M326B recovery = 40 MiB = 41,943,040 bytes (matches A326B)
BOARD_RECOVERYIMAGE_PARTITION_SIZE   := 41943040

# M326B dtbo = 8 MiB = 8,388,608 bytes
BOARD_DTBOIMG_PARTITION_SIZE         := 8388608

# M326B super = 7,864,320,000 bytes (~7500 MiB)
# A326B has 9,126,805,504 bytes (~8700 MiB) — DO NOT USE
BOARD_SUPER_PARTITION_SIZE           := 7864320000

# Dynamic partition groups (contents of super)
BOARD_SUPER_PARTITION_GROUPS := samsung_dynamic_partitions
BOARD_SAMSUNG_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product odm
# Size = super - 4 MiB overhead for partition metadata
BOARD_SAMSUNG_DYNAMIC_PARTITIONS_SIZE := 7860125696

# Filesystems
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE   := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE   := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE  := ext4

# Required when BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE / BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE are set
TARGET_COPY_OUT_VENDOR  := vendor
TARGET_COPY_OUT_PRODUCT := product

TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# Metadata partition (required for FBE and dynamic partitions)
BOARD_USES_METADATA_PARTITION := true

# AVB
BOARD_AVB_ENABLE := true
BOARD_AVB_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_RECOVERY_ALGORITHM := SHA256_RSA4096
BOARD_AVB_RECOVERY_ROLLBACK_INDEX := 1
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 1

# Recovery
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab

# Platform
TARGET_BOARD_PLATFORM := mt6853

# Crypto / FBE
# M326B uses FBE v2: aes-256-xts:aes-256-cts:v2
# keydirectory=/metadata/vold/metadata_encryption
# Confirmed from /vendor/etc/fstab.emmc on live device
TW_INCLUDE_CRYPTO          := true
TW_INCLUDE_CRYPTO_FBE      := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
TW_USE_FSCRYPT_POLICY      := 2

# TWRP theme and UI
TW_THEME := portrait_hdpi
TW_EXTRA_LANGUAGES := true
TW_SCREEN_BLANK_ON_BOOT := true
TW_INPUT_BLACKLIST := "hbtp_vm"

# Storage
TW_HAS_MTP := true
TW_MTP_DEVICE := /dev/mtp_usb
TW_INTERNAL_STORAGE_PATH := "/data/media/0"
TW_INTERNAL_STORAGE_MOUNT_POINT := "sdcard"
TW_EXTERNAL_STORAGE_PATH := "/external_sd"
TW_EXTERNAL_STORAGE_MOUNT_POINT := "external_sd"

# Brightness
TW_MAX_BRIGHTNESS     := 255
TW_DEFAULT_BRIGHTNESS := 150
TW_BRIGHTNESS_PATH    := "/sys/class/leds/lcd-backlight/brightness"

# USB / MTP
TW_EXCLUDE_DEFAULT_USB_INIT := true

# Tools
TW_INCLUDE_NTFS_3G      := true
TW_INCLUDE_REPACKTOOLS   := true
TW_INCLUDE_RESETPROP     := true
TW_INCLUDE_LIBRESETPROP  := true

# Extra libraries for decryption
BOARD_RECOVERY_ADDITIONAL_RELINK_LIBRARY_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/libion.so

# Debug logging
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD    := true

# Recovery is 64-bit only
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_VARIANT := generic

# Do not build 32-bit secondary target
TARGET_2ND_ARCH :=
TARGET_2ND_ARCH_VARIANT :=
TARGET_2ND_CPU_VARIANT :=
TARGET_SUPPORTS_32_BIT_APPS := false

