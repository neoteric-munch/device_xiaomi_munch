#!/bin/bash
#
# SPDX-FileCopyrightText: 2016 The CyanogenMod Project
# SPDX-FileCopyrightText: 2017-2024 The LineageOS Project
# SPDX-FileCopyrightText: 2026 olzhas0986
# SPDX-License-Identifier: Apache-2.0
#

set -e

DEVICE=munch
VENDOR=xiaomi

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

export TARGET_ENABLE_CHECKELF=true

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-cleanup)
            CLEAN_VENDOR=false
            ;;
        -k | --kang)
            KANG="--kang"
            ;;
        -s | --section)
            SECTION="${2}"
            shift
            CLEAN_VENDOR=false
            ;;
        *)
            SRC="${1}"
            ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

# Replace bytes in a binary file (perl regex; use \xNN escapes for raw bytes).
#   $1: file, $2: pattern, $3: replacement
function binary_regex_replace() {
    LC_ALL=C perl -0777 -pi -e "s/$2/$3/g" "$1"
}

# Append a line to a file unless it is already present.
#   $1: file, $2: line
function add_line_if_missing() {
    grep -qxF "$2" "$1" || {
        [ -n "$(tail -c1 "$1")" ] && echo >>"$1"
        echo "$2" >>"$1"
    }
}

function blob_fixup() {
    case "${1}" in
        system/framework/WfdCommon.jar)
            [ "$2" = "" ] && return 0
            apktool_patch "${2}" "${MY_DIR}/blob-patches/WfdCommon.patch"
            ;;
        vendor/etc/init/init.batterysecret.rc)
            [ "$2" = "" ] && return 0
            sed -i '/seclabel u:r:batterysecret:s0$/d' "${2}"
            ;;
        vendor/etc/init/init.mi_thermald.rc)
            [ "$2" = "" ] && return 0
            sed -i '/seclabel u:r:mi_thermald:s0$/d' "${2}"
            ;;
        vendor/etc/libnfc-nci.conf)
            [ "$2" = "" ] && return 0
            add_line_if_missing "${2}" 'LEGACY_MIFARE_READER=1'
            ;;
        vendor/etc/seccomp_policy/atfwd@2.0.policy)
            [ "$2" = "" ] && return 0
            add_line_if_missing "${2}" 'gettid: 1'
            ;;
        vendor/lib/libaudioroute_ext.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --replace-needed "libaudioroute.so" "libaudioroute-v34.so" "${2}"
            ;;
        vendor/lib/hw/audio.primary.munch.so)
            [ "$2" = "" ] && return 0
            binary_regex_replace "${2}" \
                '\/vendor\/lib\/liba2dpoffload\.so' \
                'liba2dpoffload_munch.so\x00\x00\x00\x00\x00\x00'
            "${PATCHELF}" --replace-needed "libaudioroute.so" "libaudioroute-v34.so" "${2}"
            ;;
        vendor/lib64/camera/components/com.mi.node.watermark.so)
            [ "$2" = "" ] && return 0
            grep -q "libpiex_shim.so" "${2}" || "${PATCHELF}" --add-needed "libpiex_shim.so" "${2}"
            ;;
        vendor/lib64/hw/camera.qcom.so)
            [ "$2" = "" ] && return 0
            binary_regex_replace "${2}" \
                '\x73\x74\x5F\x6C\x69\x63\x65\x6E\x73\x65\x2E\x6C\x69\x63' \
                '\x63\x61\x6D\x65\x72\x61\x5F\x63\x6E\x66\x2E\x74\x78\x74'
            ;;
        vendor/lib64/libMIAIHDRhvx_interface.so | vendor/lib64/libarcsoft_hdrplus_hvx_stub.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --clear-symbol-version remote_handle_close "${2}"
            "${PATCHELF}" --clear-symbol-version remote_handle_invoke "${2}"
            "${PATCHELF}" --clear-symbol-version remote_handle_open "${2}"
            ;;
        vendor/lib64/libarcsoft_super_night_raw.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --clear-symbol-version rpcmem_alloc "${2}"
            "${PATCHELF}" --clear-symbol-version rpcmem_free "${2}"
            "${PATCHELF}" --clear-symbol-version rpcmem_to_fd "${2}"
            ;;
        vendor/lib64/vendor.qti.hardware.camera.postproc@1.0-service-impl.so)
            [ "$2" = "" ] && return 0
            binary_regex_replace "${2}" '\x9A\x0A\x00\x94' '\x1F\x20\x03\xD5'
            ;;
        system_ext/lib64/libwfdservice.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --replace-needed "android.media.audio.common.types-V4-cpp.so" "android.media.audio.common.types-V5-cpp.so" "${2}"
            ;;
        vendor/lib64/libril-qc-hal-qmi.so)
            [ "$2" = "" ] && return 0
            binary_regex_replace "${2}" 'ro\.product\.vendor\.device' 'ro.vendor.radio.midevice'
            ;;
        vendor/lib64/libwvhidl.so | vendor/lib64/mediadrm/libwvdrmengine.so)
            [ "$2" = "" ] && return 0
            grep -q "libcrypto_shim.so" "${2}" || "${PATCHELF}" --add-needed "libcrypto_shim.so" "${2}"
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

function blob_fixup_dry() {
    blob_fixup "$1" ""
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

"${MY_DIR}/setup-makefiles.sh"
