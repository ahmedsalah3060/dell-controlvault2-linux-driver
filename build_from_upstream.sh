#!/usr/bin/env bash
# ==============================================================================
# Reproducible Build Script: Fetch OEM Broadcom driver & apply CV2 patches
# Strictly keeps the Git repository 100% free of proprietary binaries.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PATCHER="$SCRIPT_DIR/tools/patch_driver.py"

STOCK_SHA256="54fa3befc02df393077cebf96e018e3bf752cee61509897d945ab18c58c5e172"
EXPECTED_PATCHED_SHA256="308055122a9d4b7b723325a4935f25a23300ac656962c9db7e5285164233c5ab"

BROADCOM_URL="https://packages.broadcom.com/artifactory/dell-controlvault-drivers/brcm_linux_fp_5.15.377_5.15.021.0.tgz"
LAUNCHPAD_GIT="https://git.launchpad.net/~oem-solutions-engineers/libfprint-2-tod1-broadcom"

# Official Ubuntu / Debian TOD packages
TOD_DEB_URL="http://archive.ubuntu.com/ubuntu/pool/main/libf/libfprint/libfprint-2-tod1_1.94.9+tod1-1build1_amd64.deb"
LIBFPRINT_DEB_URL="http://archive.ubuntu.com/ubuntu/pool/main/libf/libfprint/libfprint-2-2_1.94.9+tod1-1build1_amd64.deb"

log_info() { echo -e "\033[1;34m[*]\033[0m $*"; }
log_ok()   { echo -e "\033[1;32m[✓]\033[0m $*"; }
log_err()  { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }

# Dependency check
for cmd in python3 sha256sum; do
    command -v "$cmd" >/dev/null || log_err "Missing required command: $cmd"
done

WORK_DIR="$(mktemp -d /tmp/cv2-build.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

log_info "Step 1/5: Fetching stock OEM driver..."
STOCK_SO=""
FW_SRC_DIR=""

# Try Broadcom Artifactory first (direct tarball, fastest and most reliable)
if command -v curl >/dev/null; then
    log_info "Downloading Broadcom driver package via curl..."
    if curl -fsSL --connect-timeout 15 "$BROADCOM_URL" -o "$WORK_DIR/driver.tgz" 2>/dev/null; then
        tar -xzf "$WORK_DIR/driver.tgz" -C "$WORK_DIR"
        STOCK_SO="$(find "$WORK_DIR" -type f -name "libfprint-2-tod-1-broadcom.so" | head -n1)"
        FW_SRC_DIR="$(find "$WORK_DIR" -type d -path "*/var/lib/fprint/fw" | head -n1)"
    fi
elif command -v wget >/dev/null; then
    log_info "Downloading Broadcom driver package via wget..."
    if wget -q --timeout=15 "$BROADCOM_URL" -O "$WORK_DIR/driver.tgz" 2>/dev/null; then
        tar -xzf "$WORK_DIR/driver.tgz" -C "$WORK_DIR"
        STOCK_SO="$(find "$WORK_DIR" -type f -name "libfprint-2-tod-1-broadcom.so" | head -n1)"
        FW_SRC_DIR="$(find "$WORK_DIR" -type d -path "*/var/lib/fprint/fw" | head -n1)"
    fi
fi

# Fallback: Try Launchpad git shallow clone if tarball failed
if [[ -z "$STOCK_SO" || ! -f "$STOCK_SO" ]]; then
    if command -v git >/dev/null; then
        log_info "Fetching from Canonical Launchpad git repository..."
        if git clone --depth 1 -b upstream "$LAUNCHPAD_GIT" "$WORK_DIR/up" 2>/dev/null; then
            STOCK_SO="$WORK_DIR/up/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so"
            FW_SRC_DIR="$WORK_DIR/up/var/lib/fprint/fw"
        fi
    fi
fi

[[ -n "$STOCK_SO" && -f "$STOCK_SO" ]] || log_err "Could not obtain stock driver binary from upstream sources."

log_info "Step 2/5: Verifying stock binary integrity..."
ACTUAL_STOCK_SHA="$(sha256sum "$STOCK_SO" | cut -d' ' -f1)"
log_info "Stock SHA256: $ACTUAL_STOCK_SHA"
if [[ "$ACTUAL_STOCK_SHA" != "$STOCK_SHA256" ]]; then
    echo "Warning: Stock binary hash differs from pinned version, but continuing..."
fi

log_info "Step 3/5: Applying 7 reverse-engineered CV2 patches..."
mkdir -p "$BUILD_DIR/driver" "$BUILD_DIR/firmware" "$BUILD_DIR/packages"
TARGET_SO="$BUILD_DIR/driver/libfprint-2-tod-1-broadcom.so"
python3 "$PATCHER" "$STOCK_SO" "$TARGET_SO"

log_info "Step 4/5: Verifying patched driver..."
PATCHED_SHA="$(sha256sum "$TARGET_SO" | cut -d' ' -f1)"
log_info "Patched SHA256: $PATCHED_SHA"
if [[ "$PATCHED_SHA" == "$EXPECTED_PATCHED_SHA256" ]]; then
    log_ok "Patched binary matches known working checksum!"
fi

# Copy firmware files
if [[ -n "$FW_SRC_DIR" && -d "$FW_SRC_DIR" ]]; then
    cp -rf "$FW_SRC_DIR"/* "$BUILD_DIR/firmware/"
    log_ok "Firmware files extracted to build/firmware/"
fi

# Step 5: Download TOD framework deb packages for Debian/Kali/Ubuntu
log_info "Step 5/5: Fetching TOD framework packages for Debian / Kali / Ubuntu..."
if command -v curl >/dev/null; then
    curl -fsSL "$TOD_DEB_URL" -o "$BUILD_DIR/packages/libfprint-2-tod1_1.94.9+tod1-1build1_amd64.deb" 2>/dev/null || true
    curl -fsSL "$LIBFPRINT_DEB_URL" -o "$BUILD_DIR/packages/libfprint-2-2_1.94.9+tod1-1build1_amd64.deb" 2>/dev/null || true
elif command -v wget >/dev/null; then
    wget -q "$TOD_DEB_URL" -O "$BUILD_DIR/packages/libfprint-2-tod1_1.94.9+tod1-1build1_amd64.deb" 2>/dev/null || true
    wget -q "$LIBFPRINT_DEB_URL" -O "$BUILD_DIR/packages/libfprint-2-2_1.94.9+tod1-1build1_amd64.deb" 2>/dev/null || true
fi

echo
log_ok "Build complete! All files generated locally in '$BUILD_DIR'."
echo "Now run:"
echo "  sudo ./install.sh"
echo
