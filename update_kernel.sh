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

# ------------------------------------------------------------------------------
# Fungsi Bantuan & Help
# ------------------------------------------------------------------------------
show_help() {
    cat << 'EOF'
======================================================================
  PENGUINOS KERNEL UPDATE AUTOMATION (XIAOMI INGRES - SM8450)
======================================================================
Penggunaan: bash device/xiaomi/ingres-kernel/update_kernel.sh [OPSI...]

Opsi Cakupan Build:
  -q, --quick, --image-only   Mode Cepat: Hanya kompilasi Kernel Image (~30-60 detik).
                              Ideal untuk ganti, update, atau menghapus root tanpa
                              mengubah modul vendor_dlkm, vendor_ramdisk, dan dtbs.
  -f, --full, --all           Mode Penuh: Kompilasi Kernel Image, 18 Techpack Modules,
                              dan perakitan DTBs/DTBO.

Opsi Integrasi Root:
  --ksu-next                  Pasang KernelSU-Next
  --bakasu                    Pasang BakaSU
  --none, --clean             Hapus root / kompilasi kernel bersih (stock GKI)
  --keep                      Pertahankan konfigurasi root yang ada saat ini

Opsi Tambahan:
  -y, --yes                   Auto-confirm (tanpa konfirmasi interaktif)
  -h, --help                  Tampilkan petunjuk ini dan keluar

Contoh Penggunaan:
  bash device/xiaomi/ingres-kernel/update_kernel.sh                         # Mode interaktif
  bash device/xiaomi/ingres-kernel/update_kernel.sh --quick --ksu-next -y  # Pasang KSU-Next
  bash device/xiaomi/ingres-kernel/update_kernel.sh --quick --bakasu -y    # Pasang BakaSU
  bash device/xiaomi/ingres-kernel/update_kernel.sh --quick --none -y      # Hapus root (stock)
  bash device/xiaomi/ingres-kernel/update_kernel.sh --full -y              # Full kernel & modules
======================================================================
EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Parsing Argumen CLI
# ------------------------------------------------------------------------------
BUILD_SCOPE=""
ROOT_CHOICE=""
SKIP_SCOPE_PROMPT=false
SKIP_ROOT_PROMPT=false
AUTO_CONFIRM=false

for arg in "$@"; do
    case "$arg" in
        -q|--quick|--image-only) BUILD_SCOPE="quick" ; SKIP_SCOPE_PROMPT=true ;;
        -f|--full|--all)         BUILD_SCOPE="full"  ; SKIP_SCOPE_PROMPT=true ;;
        --ksu-next)              ROOT_CHOICE="1"     ; SKIP_ROOT_PROMPT=true ;;
        --bakasu)                ROOT_CHOICE="2"     ; SKIP_ROOT_PROMPT=true ;;
        --none|--clean)          ROOT_CHOICE="3"     ; SKIP_ROOT_PROMPT=true ;;
        --keep)                  ROOT_CHOICE="4"     ; SKIP_ROOT_PROMPT=true ;;
        -y|--yes)                AUTO_CONFIRM=true ;;
        -h|--help)               show_help ;;
        *)
            echo "[WARN] Opsi tidak dikenal: $arg (gunakan -h atau --help untuk melihat bantuan)"
            ;;
    esac
done

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

# Jika mode quick, minimal kernel/xiaomi/sm8450 harus ada
CHECK_REPOS=("kernel/xiaomi/sm8450")
if [[ "${BUILD_SCOPE}" == "full" || "${SKIP_SCOPE_PROMPT}" == "false" ]]; then
    CHECK_REPOS=("kernel/xiaomi/sm8450" "kernel/xiaomi/sm8450-modules" "kernel/xiaomi/sm8450-devicetrees")
fi

for repo_path in "${CHECK_REPOS[@]}"; do
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

echo "[OK] Pemeriksaan repository selesai."
echo ""

# ------------------------------------------------------------------------------
# 2. Pilihan Cakupan Build & Integrasi Root
# ------------------------------------------------------------------------------
CURRENT_STEP="Konfigurasi Cakupan Build & Integrasi Root"
echo ">>> [2/5] Konfigurasi cakupan build & integrasi root..."

# A. Prompt Cakupan Build jika interaktif
if [[ "$SKIP_SCOPE_PROMPT" == "false" ]]; then
    echo "Pilih cakupan kompilasi kernel:"
    echo "  1) Quick (Hanya Kernel Image - Selesai ~30-60 detik. Ideal untuk ganti/update/hapus root) [DEFAULT]"
    echo "  2) Full  (Kernel Image + 18 External Techpack Modules + Merged DTBs/DTBO)"
    read -rp "Masukkan pilihan cakupan [1-2] (default: 1): " input_scope
    case "${input_scope:-1}" in
        2) BUILD_SCOPE="full" ;;
        1|*) BUILD_SCOPE="quick" ;;
    esac
    echo ""
fi
[[ -z "${BUILD_SCOPE}" ]] && BUILD_SCOPE="quick"

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
echo "  Cakupan build dipilih: ${BUILD_SCOPE^^}"
echo ""

# B. Prompt Root Choice jika interaktif
if [[ "$SKIP_ROOT_PROMPT" == "false" ]]; then
    echo "Pilih opsi integrasi root untuk kernel:"
    echo "  1) KernelSU-Next"
    echo "  2) BakaSU"
    echo "  3) Tidak sama sekali / None (Bersihkan root patch lama jika ada)"
    echo "  4) Pertahankan status saat ini (${CURRENT_ROOT})"
    read -rp "Masukkan pilihan root [1-4] (default: 4): " input_choice
    ROOT_CHOICE="${input_choice:-4}"
    echo ""
fi
[[ -z "${ROOT_CHOICE}" ]] && ROOT_CHOICE="4"

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
echo "  - Cakupan Build : ${BUILD_SCOPE^^}"
echo "  - Status Root   : ${NEW_ROOT_STATUS}"
echo "  - Target Dir    : ${DEST_DIR}"
echo ""

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
CURRENT_STEP="Persiapan Toolchain Clang & Batasan Sistem"
echo ">>> [4/5] Memulai kompilasi kernel (Mode: ${BUILD_SCOPE^^})..."

# Tingkatkan limit file descriptor untuk mencegah error 'Too many open files' pada sistem multi-core tinggi
ulimit -n 65535 2>/dev/null || ulimit -n 4096 2>/dev/null || true

# Tentukan alokasi paralel jobs yang aman (batasi per-modul agar tidak exhaust RAM/LTO & FD limit)
BUILD_JOBS="$(nproc)"
if (( BUILD_JOBS > 64 )); then
    MOD_JOBS=64
else
    MOD_JOBS="${BUILD_JOBS}"
fi

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

if [[ "${BUILD_SCOPE}" == "quick" ]]; then
    CURRENT_STEP="Kompilasi Kernel Image Only (Quick Mode)"
    echo "  [-] Mengompilasi Kernel Image [${BUILD_JOBS} threads] (Quick Mode)..."
    make -j"${BUILD_JOBS}" O="${OUT_DIR}" ARCH=arm64 Image
else
    CURRENT_STEP="Kompilasi Base Kernel (Image, dtbs, in-tree modules)"
    echo "  [-] Mengompilasi Base Kernel (Image, dtbs, modules) [${BUILD_JOBS} threads]..."
    make -j"${BUILD_JOBS}" O="${OUT_DIR}" ARCH=arm64 Image dtbs modules

    echo "  [-] Mengompilasi 18 External Techpack Modules (TARGET_PRODUCT=ingres) [${MOD_JOBS} threads]..."
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
        mkdir -p "${KERNEL_DIR}/sm8450-modules/${mod}"
        CURRENT_STEP="Kompilasi External Module: ${mod}"
        echo "    --> Building: ${mod}"
        make -j"${MOD_JOBS}" -C "${mod_path}" \
            KERNEL_SRC="${KERNEL_DIR}" \
            OUT_DIR="${OUT_DIR}" \
            O="${OUT_DIR}" \
            M="../sm8450-modules/${mod}" \
            TARGET_PRODUCT=ingres \
            all
    done
fi

# ------------------------------------------------------------------------------
# 5. Sinkronisasi Artifacts ke device/xiaomi/ingres-kernel
# ------------------------------------------------------------------------------
CURRENT_STEP="Sinkronisasi Artifacts ke ${DEST_DIR}"
echo ">>> [5/5] Memindahkan artefak hasil build ke ${DEST_DIR}..."

# 1. Salin Image, .config, Module.symvers, System.map
echo "  [-] Menyalin Image & symbol files..."
cp -f "${OUT_DIR}/arch/arm64/boot/Image" "${DEST_DIR}/Image"
cp -f "${OUT_DIR}/.config" "${DEST_DIR}/.config"
[[ -f "${OUT_DIR}/Module.symvers" ]] && cp -f "${OUT_DIR}/Module.symvers" "${DEST_DIR}/Module.symvers"
[[ -f "${OUT_DIR}/System.map" ]] && cp -f "${OUT_DIR}/System.map" "${DEST_DIR}/System.map"

if [[ "${BUILD_SCOPE}" == "full" ]]; then
    mkdir -p "${DEST_DIR}/dtbs"
    mkdir -p "${DEST_DIR}/vendor_ramdisk"
    mkdir -p "${DEST_DIR}/vendor_dlkm"

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
        echo "[ERROR] mkdtboimg.py tidak ditemukan di ${MKDTBOIMG}!"
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
else
    echo "  [-] [QUICK MODE] Melewati pemrosesan Techpack Modules, DTBs, dan penggantian file .ko."
    echo "  [-] Mempertahankan file vendor_dlkm/, vendor_ramdisk/, dan dtbs/ yang sudah ada."
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
echo " Versi Kernel    : ${KERNEL_VER}"
echo " Status Root     : ${NEW_ROOT_STATUS}"
echo " Cakupan Build   : ${BUILD_SCOPE^^}"
echo " Lokasi Prebuilt : ${DEST_DIR}"
if [[ "${BUILD_SCOPE}" == "full" ]]; then
    echo " Modul Ramdisk   : ${ramdisk_copied} modul disalin ke vendor_ramdisk/ (missing: ${ramdisk_missing})"
    echo " Modul DLKM      : ${dlkm_copied} modul disalin ke vendor_dlkm/ (missing: ${dlkm_missing})"
    echo " Device Trees    : dtbo.img + waipio*.dtb diperbarui di dtbs/"
else
    echo " File Diperbarui : Image & .config"
    echo " Modul & DTBs    : vendor_ramdisk/, vendor_dlkm/, dan dtbs/ tetap utuh (tidak diubah)"
fi
echo "----------------------------------------------------------------------"
echo " [CATATAN PENTING]"
echo " Sesuai instruksi, perubahan ini TIDAK otomatis di-push ke git remote."
echo " Anda dapat menguji kernel atau langsung menjalankan build ROM:"
echo "   ./rom-build.sh ingres -t userdebug -g"
echo "======================================================================"
