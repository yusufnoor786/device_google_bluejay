#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-FileCopyrightText: The Calyx Institute
# SPDX-License-Identifier: Apache-2.0
#

# Inherit some common stuff
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Face unlock 
$(call inherit-product-if-exists, vendor/google/faceunlock/config.mk)

# Camera
$(call inherit-product-if-exists, vendor/google/camera/config.mk)

# ViPER4Android FX
$(call inherit-product, packages/apps/ViPER4AndroidFX/config.mk)

PRODUCT_ENFORCE_ARTIFACT_PATH_REQUIREMENTS := false

# Inherit device configuration
DEVICE_CODENAME := bluejay
DEVICE_PATH := device/google/bluejay
VENDOR_PATH := vendor/google/bluejay
$(call inherit-product, $(DEVICE_PATH)/aosp_$(DEVICE_CODENAME).mk)

# Device identifier. This must come after all inclusions
PRODUCT_BRAND := google
PRODUCT_MODEL := Pixel 6a
PRODUCT_NAME := lineage_$(DEVICE_CODENAME)

# MistOS
MISTOS_MAINTAINER := Zabuka_Zuzu
MIST_BUILD_TYPE := OFFICIAL
WITH_GMS := true
TARGET_ENABLE_BLUR := true
TARGET_SUPPORTS_QUICK_TAP := true
BYPASS_CHARGE_SUPPORTED := true
TARGET_HAS_UDFPS := true

# Boot animation
TARGET_SCREEN_HEIGHT := 2400
TARGET_SCREEN_WIDTH := 1080

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="bluejay-user 16 BP4A.251205.006 14401865 release-keys" \
    BuildFingerprint=google/bluejay/bluejay:16/BP4A.251205.006/14401865:user/release-keys \
    DeviceProduct=$(DEVICE_CODENAME)

$(call inherit-product, $(VENDOR_PATH)/$(DEVICE_CODENAME)-vendor.mk)
