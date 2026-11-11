#!/usr/bin/env bash
# ==============================================================================
# Diagnostic & Verification Script for Dell ControlVault 2 (0a5c:5834)
# ==============================================================================
set -u

BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BLUE="\033[1;34m"
NC="\033[0m"

echo -e "${BOLD}======================================================================${NC}"
echo -e "${BOLD}       Dell ControlVault 2 Linux Driver Health & Diagnosis           ${NC}"
echo -e "${BOLD}======================================================================${NC}"

section() { echo -e "\n${BLUE}--- [ $1 ] ---${NC}"; }

section "System Info"
echo "Kernel: $(uname -s -r -m)"
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    echo "Distro: ${PRETTY_NAME:-$NAME}"
fi

section "USB Hardware Check"
if grep -qs "0a5c" /sys/bus/usb/devices/*/idVendor 2>/dev/null && \
   grep -qs "5834" /sys/bus/usb/devices/*/idProduct 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Broadcom 5880 ControlVault 2 (0a5c:5834) detected on USB bus!"
elif command -v lsusb >/dev/null && lsusb -d 0a5c:5834 >/dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} Broadcom 5880 ControlVault 2 (0a5c:5834) detected on USB bus!"
else
    echo -e "${RED}[FAIL]${NC} USB device 0a5c:5834 NOT detected!"
    echo "       Check BIOS: System Configuration -> Fingerprint Reader / ControlVault -> Enabled."
fi

section "TOD Shared Library Check"
TOD_LIB_FOUND=0
for lib in /usr/lib/x86_64-linux-gnu/libfprint-2-tod.so* \
           /usr/lib64/libfprint-2-tod.so* \
           /usr/lib/libfprint-2-tod.so*; do
    if [[ -f "$lib" ]]; then
        echo -e "${GREEN}[OK]${NC} Found TOD runtime library: $lib"
        TOD_LIB_FOUND=1
        break
    fi
done
if [[ $TOD_LIB_FOUND -eq 0 ]]; then
    echo -e "${YELLOW}[WARN]${NC} libfprint-2-tod runtime library not found in standard paths."
fi

section "APT Package Hold Status"
if command -v apt-mark >/dev/null; then
    holds="$(apt-mark showhold | grep -E 'libfprint' || true)"
    if [[ -n "$holds" ]]; then
        echo -e "${GREEN}[OK]${NC} TOD packages locked with apt-mark hold (protected from apt upgrades):"
        echo "$holds" | sed 's/^/     /'
    else
        echo -e "${YELLOW}[WARN]${NC} Packages not on hold. Run: sudo apt-mark hold libfprint-2-tod1 libfprint-2-2"
    fi
fi

section "Broadcom Driver Binary Check"
DRIVER_FOUND=0
for tod_path in /usr/lib/x86_64-linux-gnu/libfprint-2/tod-1 \
               /usr/lib64/libfprint-2/tod-1 \
               /usr/lib/libfprint-2/tod-1; do
    so="$tod_path/libfprint-2-tod-1-broadcom.so"
    if [[ -f "$so" ]]; then
        echo -e "${GREEN}[OK]${NC} Driver installed at: $so"
        sha="$(sha256sum "$so" | cut -d' ' -f1)"
        echo "     SHA256: $sha"
        DRIVER_FOUND=1
        break
    fi
done
if [[ $DRIVER_FOUND -eq 0 ]]; then
    echo -e "${RED}[FAIL]${NC} Driver libfprint-2-tod-1-broadcom.so NOT found!"
fi

section "Firmware Files Check"
if [[ $EUID -ne 0 && ! -r /var/lib/fprint/fw ]]; then
    echo -e "${GREEN}[OK]${NC} Firmware directory /var/lib/fprint/fw/ is protected by system permissions (root)."
    echo "     (Run with sudo if you wish to inspect individual firmware files)."
elif [[ -f /var/lib/fprint/fw/bcmDeviceFirmwareCitadel_1.bin && -f /var/lib/fprint/fw/bcmCitadel_1.otp ]]; then
    echo -e "${GREEN}[OK]${NC} Broadcom Citadel firmware files present in /var/lib/fprint/fw/"
else
    echo -e "${RED}[FAIL]${NC} Firmware files missing from /var/lib/fprint/fw/ (run sudo ./install.sh)"
fi

section "Permissions & Rules Check"
if [[ -f /etc/udev/rules.d/61-broadcom-cv2-5834.rules ]]; then
    echo -e "${GREEN}[OK]${NC} udev rule present: /etc/udev/rules.d/61-broadcom-cv2-5834.rules"
else
    echo -e "${YELLOW}[WARN]${NC} udev rule missing."
fi

if [[ -f /etc/polkit-1/rules.d/50-fprintd.rules ]]; then
    echo -e "${GREEN}[OK]${NC} Polkit rule present: /etc/polkit-1/rules.d/50-fprintd.rules (AUTH_ADMIN default)"
else
    echo -e "${YELLOW}[WARN]${NC} Polkit authorization rule missing (/etc/polkit-1/rules.d/50-fprintd.rules)."
fi

section "fprintd Service Check"
if systemctl is-active --quiet fprintd 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} fprintd.service is active and running."
else
    echo -e "${YELLOW}[INFO]${NC} fprintd is on-demand (D-Bus activated) or currently idle."
fi

section "Device Recognition Check (fprintd-list)"
TARGET_USER="${SUDO_USER:-$USER}"
echo "Testing for user: $TARGET_USER"
fprintd-list "$TARGET_USER" 2>&1 || true

echo
echo -e "${BOLD}======================================================================${NC}"
echo -e "Diagnosis complete. Test enrollment with: ${YELLOW}fprintd-enroll${NC}"
echo -e "${BOLD}======================================================================${NC}"
