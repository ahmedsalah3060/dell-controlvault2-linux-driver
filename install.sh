#!/usr/bin/env bash
# ==============================================================================
# Installer for Dell ControlVault 2 Linux Driver (BCM5880 / 0a5c:5834)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
DRIVER_SO="$BUILD_DIR/driver/libfprint-2-tod-1-broadcom.so"
FW_DIR_SRC="$BUILD_DIR/firmware"
RULES_DIR="$SCRIPT_DIR/rules"

log_info()    { echo -e "\033[1;34m[*]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[✓]\033[0m $*"; }
log_warn()    { echo -e "\033[1;33m[!]\033[0m $*"; }
log_err()     { echo -e "\033[1;31m[✗]\033[0m $*" >&2; }

# Check root elevation
if [[ $EUID -ne 0 ]]; then
    log_info "Elevating to root permissions..."
    exec sudo bash "$0" "$@"
fi

# Step 0: Ensure driver has been built locally
if [[ ! -f "$DRIVER_SO" ]]; then
    log_warn "Patched driver not found in build directory."
    log_info "Running build_from_upstream.sh automatically..."
    bash "$SCRIPT_DIR/build_from_upstream.sh"
fi

[[ -f "$DRIVER_SO" ]] || { log_err "Build failed. Run ./build_from_upstream.sh manually."; exit 1; }

# Check architecture
[[ "$(uname -m)" == "x86_64" ]] || { log_err "Broadcom driver requires x86_64 (detected: $(uname -m))"; exit 1; }

# Step 1: Ensure TOD-enabled libfprint is installed
log_info "Step 1/5: Checking for TOD-enabled libfprint runtime..."
if command -v apt-get >/dev/null; then
    if ! dpkg -l | grep -q "libfprint-2-tod1"; then
        log_info "Installing libfprint-2-tod1 and fprintd via apt..."
        apt-get update -qq || true
        apt-get install -y libfprint-2-tod1 fprintd libpam-fprintd || true
    fi
elif command -v zypper >/dev/null; then
    zypper install -y libfprint-2-tod1 fprintd pam_fprintd || true
elif command -v pacman >/dev/null; then
    log_info "On Arch/Manjaro, ensure 'libfprint-tod' and 'fprintd' are installed from AUR."
fi

# Step 2: Determine TOD directory
log_info "Step 2/5: Locating TOD driver directory..."
TOD_DIR=""
for candidate in \
    "/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1" \
    "/usr/lib64/libfprint-2/tod-1" \
    "/usr/lib/libfprint-2/tod-1"; do
    if [[ -d "$(dirname "$candidate")" || -d "$candidate" ]]; then
        TOD_DIR="$candidate"
        break
    fi
done
TOD_DIR="${TOD_DIR:-/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1}"
mkdir -p "$TOD_DIR"
log_success "Target TOD directory: $TOD_DIR"

# Step 3: Install driver binary
log_info "Step 3/5: Installing patched driver..."
install -m 644 "$DRIVER_SO" "$TOD_DIR/libfprint-2-tod-1-broadcom.so"
log_success "Installed $TOD_DIR/libfprint-2-tod-1-broadcom.so"

# Step 4: Install firmware blobs
log_info "Step 4/5: Installing firmware blobs..."
mkdir -p /var/lib/fprint/fw
if [[ -d "$FW_DIR_SRC" ]]; then
    cp -rf "$FW_DIR_SRC"/* /var/lib/fprint/fw/
    chmod 644 /var/lib/fprint/fw/* || true
    chmod 755 /var/lib/fprint/fw || true
    log_success "Firmware installed to /var/lib/fprint/fw/"
fi

# Step 5: Install udev and Polkit rules
log_info "Step 5/5: Configuring udev and Polkit security rules..."
mkdir -p /etc/udev/rules.d /etc/polkit-1/rules.d
cp -f "$RULES_DIR/61-broadcom-cv2-5834.rules" /etc/udev/rules.d/
cp -f "$RULES_DIR/50-fprintd.rules" /etc/polkit-1/rules.d/

udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --action=add --subsystem-match=usb --attr-match=idVendor=0a5c --attr-match=idProduct=5834 2>/dev/null || true

# Fix systemd masking and restart
if [[ -L /etc/systemd/system/fprintd.service ]]; then
    rm -f /etc/systemd/system/fprintd.service
fi
systemctl unmask fprintd 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true
systemctl restart fprintd 2>/dev/null || true
systemctl enable fprintd 2>/dev/null || true

echo
echo -e "\033[1;32m======================================================================\033[0m"
echo -e "\033[1;32m[✓] Installation complete! Ready for enrollment.                      \033[0m"
echo -e "\033[1;32m======================================================================\033[0m"
echo "  1. Enroll:  fprintd-enroll"
echo "  2. Verify:  fprintd-verify"
echo "  3. Enable:  sudo pam-auth-update (check [*] Fingerprint authentication)"
echo

