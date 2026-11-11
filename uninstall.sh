#!/usr/bin/env bash
# ==============================================================================
# Dell ControlVault 2 Linux Driver Uninstaller
# ==============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    exec sudo bash "$0" "$@"
fi

echo "[*] Uninstalling Dell ControlVault 2 driver..."

# Remove driver binary
for tod in /usr/lib/x86_64-linux-gnu/libfprint-2/tod-1 \
           /usr/lib64/libfprint-2/tod-1 \
           /usr/lib/libfprint-2/tod-1; do
    if [[ -f "$tod/libfprint-2-tod-1-broadcom.so" ]]; then
        echo "[*] Removing $tod/libfprint-2-tod-1-broadcom.so"
        rm -f "$tod/libfprint-2-tod-1-broadcom.so"
    fi
done

# Remove rules
echo "[*] Removing udev and Polkit rules..."
rm -f /etc/udev/rules.d/61-broadcom-cv2-5834.rules
rm -f /etc/polkit-1/rules.d/50-fprintd.rules

# Reload rules and restart daemon
udevadm control --reload-rules 2>/dev/null || true
systemctl restart fprintd 2>/dev/null || true

echo "[✓] Uninstallation complete."
echo "Note: Firmware files in /var/lib/fprint/fw/ were kept. Delete manually if needed:"
echo "      sudo rm -rf /var/lib/fprint/fw"

