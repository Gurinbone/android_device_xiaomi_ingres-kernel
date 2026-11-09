#!/usr/bin/env bash
# ==============================================================================
# Script Otomatisasi Update Prebuilt Kernel Xiaomi Ingres (sm8450)
# Penempatan: device/xiaomi/ingres-kernel/update_kernel.sh
# Dapat dijalankan dengan: bash device/xiaomi/ingres-kernel/update_kernel.sh
# ==============================================================================

set -eo pipefail

CURRENT_STEP="Inisialisasi Lingkungan"

# ------------------------------------------------------------------------------
# Error & Signal Handling
# ------------------------------------------------------------------------------
error_handler() {
    local exit_code="$1"
    local line_no="$2"
    local failed_cmd="$3"
    echo ""
    echo "======================================================================"
    echo " [ERROR] SCRIPT GAGAL / TERHENTI!"
    echo "======================================================================"
    echo "  Tahap Terakhir : ${CURRENT_STEP}"
    echo "  Status Exit    : ${exit_code}"
    echo "  Baris Script   : ${line_no}"
    echo "  Perintah Gagal : ${failed_cmd}"
    echo "----------------------------------------------------------------------"
    echo "  Proses otomatisasi kernel terhenti karena terjadi error pada perintah di atas."
    echo "  Silakan periksa log compiler / pesan error sebelum banner ini."
    echo "======================================================================"
    echo ""
    exit "${exit_code}"
}

trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR
trap 'echo -e "\n[INFO] Script dibatalkan oleh pengguna (SIGINT)."; exit 130' INT

# ------------------------------------------------------------------------------
# 0. Resolusi Path Workspace & Direktori
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

if [[ ! -d "${ROOT_DIR}/build" || ! -d "${ROOT_DIR}/device/xiaomi/ingres-kernel" ]]; then
    echo "[ERROR] Root workspace PenguinOS tidak valid: ${ROOT_DIR}"
    echo "Pastikan script berada di device/xiaomi/ingres-kernel/update_kernel.sh"
    exit 1
fi

DEST_DIR="${SCRIPT_DIR}"
KERNEL_DIR="${ROOT_DIR}/kernel/xiaomi/sm8450"
MODULES_DIR="${ROOT_DIR}/kernel/xiaomi/sm8450-modules"
DEVTREES_DIR="${ROOT_DIR}/kernel/xiaomi/sm8450-devicetrees"
OUT_DIR="${KERNEL_DIR}/out"

echo "======================================================================"
echo "    PENGUINOS KERNEL UPDATE AUTOMATION (XIAOMI INGRES - SM8450)       "
echo "======================================================================"
echo "Root Workspace: ${ROOT_DIR}"
echo "Destinasi     : ${DEST_DIR}"
echo ""

# ------------------------------------------------------------------------------
# 1. Pengecekan & Clone Repository Kernel yang Dibutuhkan
# ------------------------------------------------------------------------------
CURRENT_STEP="Pemeriksaan & Clone Repository Kernel"
echo ">>> [1/5] Memeriksa repository kernel yang dibutuhkan..."

declare -A REQUIRED_REPOS=(
    ["kernel/xiaomi/sm8450"]="https://github.com/Gurinbone/android_kernel_xiaomi_sm8450.git"
    ["kernel/xiaomi/sm8450-modules"]="https://github.com/LineageOS/android_kernel_xiaomi_sm8450-modules.git"
    ["kernel/xiaomi/sm8450-devicetrees"]="https://github.com/Gurinbone/android_kernel_xiaomi_sm8450-devicetrees.git"
)

for repo_path in "kernel/xiaomi/sm8450" "kernel/xiaomi/sm8450-modules" "kernel/xiaomi/sm8450-devicetrees"; do
    target_dir="${ROOT_DIR}/${repo_path}"
    repo_url="${REQUIRED_REPOS[$repo_path]}"
    if [[ -d "${target_dir}/.git" ]]; then
        echo "  [OK] ${repo_path} sudah ada."
    else
        echo "  [CLONE] Meng-clone ${repo_url} (branch lineage-24.0) ke ${repo_path}..."
        mkdir -p "$(dirname "${target_dir}")"
        git clone -b lineage-24.0 "${repo_url}" "${target_dir}"
    fi
done

echo "[OK] Seluruh repository kernel siap."
echo ""

# ------------------------------------------------------------------------------
# 2. Pengecekan & Manajemen Integrasi Root (KernelSU-Next / BakaSU / None)
# ------------------------------------------------------------------------------
CURRENT_STEP="Konfigurasi Integrasi Root (KernelSU / BakaSU)"
echo ">>> [2/5] Memeriksa status integrasi root..."

detect_root() {
    local kdir="$1"
    if [[ -d "${kdir}/KernelSU-Next" ]]; then
        echo "KernelSU-Next"
    elif [[ -d "${kdir}/KernelSU" ]]; then
        local origin_url
        origin_url=$(git -C "${kdir}/KernelSU" remote get-url origin 2>/dev/null || echo "")
        if [[ "$origin_url" =~ [Bb]aka ]]; then
            echo "BakaSU"
        else
            echo "KernelSU"
        fi
    elif [[ -L "${kdir}/drivers/kernelsu" ]] || [[ -d "${kdir}/drivers/kernelsu" ]]; then
        echo "KernelSU (Unknown)"
    else
        echo "Tidak Ada (Stock / Clean)"
    fi
}

cleanup_root() {
    local kdir="$1"
    echo "  [-] Menghapus patch root (KernelSU/BakaSU) yang ada..."
    rm -rf "${kdir}/KernelSU" "${kdir}/KernelSU-Next" "${kdir}/BakaSU" "${kdir}/drivers/kernelsu"
    (
        cd "${kdir}"
        git checkout -- drivers/Kconfig drivers/Makefile 2>/dev/null || true
    )
    echo "  [+] Konfigurasi drivers/Kconfig dan drivers/Makefile dikembalikan ke kondisi clean."
}

CURRENT_ROOT="$(detect_root "${KERNEL_DIR}")"
echo "  Status root saat ini: ${CURRENT_ROOT}"
echo ""

# Parse opsi via argumen CLI atau interactive prompt
ROOT_CHOICE=""
SKIP_PROMPT=false
AUTO_CONFIRM=false

for arg in "$@"; do
    case "$arg" in
        --ksu-next)     ROOT_CHOICE="1" ; SKIP_PROMPT=true ;;
        --bakasu)       ROOT_CHOICE="2" ; SKIP_PROMPT=true ;;
        --none|--clean) ROOT_CHOICE="3" ; SKIP_PROMPT=true ;;
        --keep)         ROOT_CHOICE="4" ; SKIP_PROMPT=true ;;
        -y|--yes)       AUTO_CONFIRM=true ;;
    esac
done

if [[ "$SKIP_PROMPT" == "false" ]]; then
    echo "Pilih opsi integrasi root untuk kernel:"
    echo "  1) KernelSU-Next"
    echo "  2) BakaSU"
    echo "  3) Tidak sama sekali / None (Bersihkan root patch lama jika ada)"
    echo "  4) Pertahankan status saat ini (${CURRENT_ROOT})"
    read -rp "Masukkan pilihan [1-4] (default: 4): " input_choice
    ROOT_CHOICE="${input_choice:-4}"
fi

case "$ROOT_CHOICE" in
    1)
        echo "  [+] Memilih KernelSU-Next..."
        cleanup_root "${KERNEL_DIR}"
        (
            cd "${KERNEL_DIR}"
            curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -
        )
        ;;
    2)
        echo "  [+] Memilih BakaSU..."
        cleanup_root "${KERNEL_DIR}"
        (
            cd "${KERNEL_DIR}"
            curl -LSs "https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh" | bash -
        )
        ;;
    3)
        echo "  [+] Menghapus seluruh patch root..."
        cleanup_root "${KERNEL_DIR}"
        ;;
    4|*)
        echo "  [*] Mempertahankan kondisi saat ini: ${CURRENT_ROOT}"
        ;;
esac

NEW_ROOT_STATUS="$(detect_root "${KERNEL_DIR}")"
echo "  Status root setelah konfigurasi: ${NEW_ROOT_STATUS}"
echo ""

# ------------------------------------------------------------------------------
# 3. Konfirmasi Eksekusi Build Kernel
# ------------------------------------------------------------------------------
CURRENT_STEP="Konfirmasi Eksekusi Build"
echo ">>> [3/5] Konfirmasi eksekusi kompilasi kernel..."

if [[ "${AUTO_CONFIRM}" != "true" ]]; then
    read -rp "Lanjutkan proses kompilasi kernel dan pemindahan artifacts ke device/xiaomi/ingres-kernel? (y/N): " confirm_build
    if [[ ! "$confirm_build" =~ ^[yY]$ ]]; then
        echo "Proses dibatalkan oleh pengguna."
        exit 0
    fi
fi

# ------------------------------------------------------------------------------
# 4. Kompilasi Kernel, Modules, dan DTBs
# ------------------------------------------------------------------------------
CURRENT_STEP="Persiapan Toolchain Clang"
echo ">>> [4/5] Memulai kompilasi kernel..."

CLANG_DIR="${ROOT_DIR}/prebuilts/clang/host/linux-x86/clang-r584948"
if [[ ! -d "${CLANG_DIR}/bin" ]]; then
    echo "[ERROR] Prebuilt Clang tidak ditemukan di ${CLANG_DIR}!"
    exit 1
fi

export PATH="${CLANG_DIR}/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-
export CC=clang
export LD=ld.lld
export LLVM=1
export LLVM_IAS=1

mkdir -p "${OUT_DIR}"

CURRENT_STEP="Penyusunan Defconfig & Fragments"
echo "  [-] Menggabungkan defconfig & fragments..."
cd "${KERNEL_DIR}"
make O="${OUT_DIR}" ARCH=arm64 gki_defconfig
./scripts/kconfig/merge_config.sh -m -O "${OUT_DIR}" "${OUT_DIR}/.config" \
    arch/arm64/configs/vendor/waipio_GKI.config \
    arch/arm64/configs/vendor/xiaomi_GKI.config \
    arch/arm64/configs/vendor/ingres_GKI.config \
    arch/arm64/configs/vendor/debugfs.config

# Jika root patch terdeteksi aktif, pastikan CONFIG_KSU=y
if [[ -d "${KERNEL_DIR}/drivers/kernelsu" ]] || [[ -d "${KERNEL_DIR}/KernelSU" ]] || [[ -d "${KERNEL_DIR}/KernelSU-Next" ]]; then
    echo "  [+] Menambahkan CONFIG_KSU=y ke defconfig..."
    echo "CONFIG_KSU=y" >> "${OUT_DIR}/.config"
fi

make O="${OUT_DIR}" ARCH=arm64 olddefconfig

CURRENT_STEP="Kompilasi Base Kernel (Image, dtbs, in-tree modules)"
echo "  [-] Mengompilasi Base Kernel (Image, dtbs, modules) [$(nproc) threads]..."
make -j"$(nproc)" O="${OUT_DIR}" ARCH=arm64 Image dtbs modules

echo "  [-] Mengompilasi 18 External Techpack Modules (TARGET_PRODUCT=ingres)..."
EXT_MODULES=(
    "qcom/opensource/mmrm-driver"
    "qcom/opensource/audio-kernel"
    "qcom/opensource/camera-kernel"
    "qcom/opensource/cvp-kernel"
    "qcom/opensource/dataipa/drivers/platform/msm"
    "qcom/opensource/datarmnet/core"
    "qcom/opensource/datarmnet-ext/aps"
    "qcom/opensource/datarmnet-ext/offload"
    "qcom/opensource/datarmnet-ext/shs"
    "qcom/opensource/datarmnet-ext/perf"
    "qcom/opensource/datarmnet-ext/perf_tether"
    "qcom/opensource/datarmnet-ext/sch"
    "qcom/opensource/datarmnet-ext/wlan"
    "qcom/opensource/display-drivers/msm"
    "qcom/opensource/eva-kernel"
    "qcom/opensource/video-driver"
    "qcom/opensource/wlan/qcacld-3.0/.qca6490"
    "qcom/opensource/wlan/qcacld-3.0/.qca6750"
)

for mod in "${EXT_MODULES[@]}"; do
    mod_path="${MODULES_DIR}/${mod}"
    if [[ ! -d "${mod_path}" ]]; then
        echo "  [WARN] Modul directory tidak ditemukan: ${mod_path}, melewati..."
        continue
    fi
    CURRENT_STEP="Kompilasi External Module: ${mod}"
    echo "    --> Building: ${mod}"
    make -j"$(nproc)" -C "${mod_path}" \
        KERNEL_SRC="${KERNEL_DIR}" \
        OUT_DIR="${OUT_DIR}" \
        O="${OUT_DIR}" \
        M="../sm8450-modules/${mod}" \
        TARGET_PRODUCT=ingres \
        all
done

# ------------------------------------------------------------------------------
# 5. Sinkronisasi Artifacts ke device/xiaomi/ingres-kernel
# ------------------------------------------------------------------------------
CURRENT_STEP="Sinkronisasi Artifacts ke ${DEST_DIR}"
echo ">>> [5/5] Memindahkan artefak hasil build ke ${DEST_DIR}..."

mkdir -p "${DEST_DIR}/dtbs"
mkdir -p "${DEST_DIR}/vendor_ramdisk"
mkdir -p "${DEST_DIR}/vendor_dlkm"

# 1. Salin Image, .config, Module.symvers, System.map
echo "  [-] Menyalin Image & symbol files..."
cp -f "${OUT_DIR}/arch/arm64/boot/Image" "${DEST_DIR}/Image"
cp -f "${OUT_DIR}/.config" "${DEST_DIR}/.config"
cp -f "${OUT_DIR}/Module.symvers" "${DEST_DIR}/Module.symvers"
cp -f "${OUT_DIR}/System.map" "${DEST_DIR}/System.map"

# 2. Penggabungan Techpack Device Trees (merge_dtbs.py) & Perakitan dtbo.img
CURRENT_STEP="Penggabungan & Perakitan DTBs / DTBO (merge_dtbs.py)"
echo "  [-] Menyiapkan tool fdtoverlaymerge..."
mkdir -p "${DEST_DIR}/tools/bin"
if [[ ! -x "${DEST_DIR}/tools/bin/fdtoverlaymerge" ]]; then
    echo '#define DTC_VERSION "DTC 1.7.0-Android-build"' > "${DEST_DIR}/tools/bin/version_gen.h"
    gcc -O2 -DNO_YAML \
        -I"${ROOT_DIR}/external/dtc" \
        -I"${ROOT_DIR}/external/dtc/libfdt" \
        -I"${DEST_DIR}/tools/bin" \
        "${ROOT_DIR}/external/dtc/fdtoverlaymerge.c" \
        "${ROOT_DIR}/external/dtc/util.c" \
        "${ROOT_DIR}/external/dtc/libfdt/"*.c \
        -o "${DEST_DIR}/tools/bin/fdtoverlaymerge"
fi

MERGE_DTBS_PY="${DEST_DIR}/tools/merge_dtbs.py"
if [[ ! -f "${MERGE_DTBS_PY}" ]]; then
    echo "[ERROR] ${MERGE_DTBS_PY} tidak ditemukan!"
    exit 1
fi

echo "  [-] Menjalankan merge_dtbs.py untuk menggabungkan Base DTB dan Techpack Overlays..."
DTBS_WORK="${KERNEL_DIR}/out/dtbs_merge_work"
rm -rf "${DTBS_WORK}"
mkdir -p "${DTBS_WORK}/src" "${DTBS_WORK}/base" "${DTBS_WORK}/out"

cp -r "${OUT_DIR}/arch/arm64/boot/dts/vendor" "${DTBS_WORK}/src/"
mv "${DTBS_WORK}/src/vendor/"*/*.dtb "${DTBS_WORK}/src/vendor/"*/*.dtbo "${DTBS_WORK}/base/"

PATH="${DEST_DIR}/tools/bin:${ROOT_DIR}/out/host/linux-x86/bin:$PATH" \
    python3 "${MERGE_DTBS_PY}" \
    --base "${DTBS_WORK}/base" \
    --techpack "${DTBS_WORK}/src/vendor" \
    --out "${DTBS_WORK}/out"

echo "  [-] Menyalin merged DTB ke ${DEST_DIR}/dtbs/..."
cp -f "${DTBS_WORK}/out"/waipio*.dtb "${DEST_DIR}/dtbs/"

MKDTBOIMG="${ROOT_DIR}/system/libufdt/utils/src/mkdtboimg.py"
if [[ -f "${MKDTBOIMG}" ]]; then
    echo "  [-] Menyusun merged dtbo.img (page_size=4096)..."
    python3 "${MKDTBOIMG}" create "${DEST_DIR}/dtbs/dtbo.img" --page_size=4096 $(find "${DTBS_WORK}/out" -type f -name "*.dtbo" | sort)
else
    echo "  [ERROR] mkdtboimg.py tidak ditemukan di ${MKDTBOIMG}!"
    exit 1
fi

# 3. Sinkronisasi Kernel Modules (.ko) & Stripping Debug Symbols
CURRENT_STEP="Sinkronisasi & Stripping Modul Kernel"
STRIP_TOOL="${CLANG_DIR}/bin/llvm-strip"
echo "  [-] Mengindeks modul-modul yang baru dikompilasi..."
declare -A KO_MAP=()
while IFS= read -r ko_file; do
    base_name="$(basename "${ko_file}")"
    KO_MAP["${base_name}"]="${ko_file}"
done < <(find "${OUT_DIR}" "${KERNEL_DIR}/sm8450-modules" "${MODULES_DIR}" -type f -name "*.ko" 2>/dev/null)

# Penanganan fallback wlan.ko -> qca_cld3_wlan.ko jika diperlukan
if [[ -n "${KO_MAP["wlan.ko"]:-}" && -z "${KO_MAP["qca_cld3_wlan.ko"]:-}" ]]; then
    KO_MAP["qca_cld3_wlan.ko"]="${KO_MAP["wlan.ko"]}"
fi

echo "  [-] Menyalin dan melakukan stripping modul ke vendor_ramdisk/..."
ramdisk_copied=0
ramdisk_missing=0
if [[ -f "${DEST_DIR}/vendor_ramdisk/modules.load.recovery" ]]; then
    while IFS= read -r mod || [[ -n "$mod" ]]; do
        [[ -z "$mod" || "$mod" =~ ^# ]] && continue
        if [[ -n "${KO_MAP["${mod}"]:-}" ]]; then
            cp -f "${KO_MAP["${mod}"]}" "${DEST_DIR}/vendor_ramdisk/${mod}"
            if [[ -x "${STRIP_TOOL}" ]]; then
                "${STRIP_TOOL}" --strip-debug "${DEST_DIR}/vendor_ramdisk/${mod}" 2>/dev/null || true
            fi
            ((ramdisk_copied++)) || true
        else
            echo "    [WARN] Modul ${mod} tidak ditemukan di build output!"
            ((ramdisk_missing++)) || true
        fi
    done < "${DEST_DIR}/vendor_ramdisk/modules.load.recovery"
fi

echo "  [-] Menyalin dan melakukan stripping modul ke vendor_dlkm/..."
dlkm_copied=0
dlkm_missing=0
if [[ -f "${DEST_DIR}/vendor_dlkm/modules.load" ]]; then
    while IFS= read -r mod || [[ -n "$mod" ]]; do
        [[ -z "$mod" || "$mod" =~ ^# ]] && continue
        if [[ -n "${KO_MAP["${mod}"]:-}" ]]; then
            cp -f "${KO_MAP["${mod}"]}" "${DEST_DIR}/vendor_dlkm/${mod}"
            if [[ -x "${STRIP_TOOL}" ]]; then
                "${STRIP_TOOL}" --strip-debug "${DEST_DIR}/vendor_dlkm/${mod}" 2>/dev/null || true
            fi
            ((dlkm_copied++)) || true
        else
            echo "    [WARN] Modul ${mod} tidak ditemukan di build output!"
            ((dlkm_missing++)) || true
        fi
    done < "${DEST_DIR}/vendor_dlkm/modules.load"
fi

# Sinkronisasi blocklist jika ada dari source
if [[ -f "${KERNEL_DIR}/modules.vendor_blocklist.msm.waipio" ]]; then
    cp -f "${KERNEL_DIR}/modules.vendor_blocklist.msm.waipio" "${DEST_DIR}/vendor_ramdisk/modules.blocklist"
    cp -f "${KERNEL_DIR}/modules.vendor_blocklist.msm.waipio" "${DEST_DIR}/vendor_dlkm/modules.blocklist"
fi

# ------------------------------------------------------------------------------
# Ringkasan Selesai
# ------------------------------------------------------------------------------
CURRENT_STEP="Penyelesaian"
KERNEL_VER="$(strings "${DEST_DIR}/Image" | grep 'Linux version 5.10' | head -n 1 | cut -d ' ' -f 3 || echo "5.10.x")"

echo ""
echo "======================================================================"
echo " [SUCCESS] UPDATE PREBUILT KERNEL BERHASIL!"
echo "======================================================================"
echo " Versi Kernel   : ${KERNEL_VER}"
echo " Status Root    : ${NEW_ROOT_STATUS}"
echo " Lokasi Prebuilt : ${DEST_DIR}"
echo " Modul Ramdisk  : ${ramdisk_copied} modul disalin ke vendor_ramdisk/ (missing: ${ramdisk_missing})"
echo " Modul DLKM     : ${dlkm_copied} modul disalin ke vendor_dlkm/ (missing: ${dlkm_missing})"
echo " Device Trees   : dtbo.img + waipio*.dtb diperbarui di dtbs/"
echo "----------------------------------------------------------------------"
echo " [CATATAN PENTING]"
echo " Sesuai instruksi, perubahan ini TIDAK di-commit dan TIDAK di-push."
echo " Anda dapat menguji kernel atau menjalankan build ROM terlebih dahulu."
echo " Jika ingin commit nanti, Anda dapat menggunakan:"
echo "   cd ${DEST_DIR} && ./gencommit.sh"
echo "======================================================================"
