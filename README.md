# Dell ControlVault 2 (BCM5880 / USB 0a5c:5834) Linux Fingerprint Driver

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Hardware: Broadcom 5880](https://img.shields.io/badge/Hardware-0a5c%3A5834-orange.svg)](https://linux-hardware.org/?id=usb:0a5c-5834)
[![Platform: Linux x86_64](https://img.shields.io/badge/Platform-Linux%20x86__64-brightgreen.svg)](#supported-systems)

A clean, reproducible reverse-engineering patch set that enables **Dell ControlVault 2 / Broadcom BCM5880** fingerprint sensors on modern Linux distributions (Kali Linux, Ubuntu, Debian, Linux Mint, Arch, Fedora).

> [!NOTE]
> This repository is **100% free of proprietary binaries and firmware**. It fetches the official OEM upstream driver locally at build time, verifies cryptographic checksums, and applies 7 reverse-engineered byte-level patches locally.

---

## 📌 Supported Hardware

Works on all Dell laptops and mobile workstations featuring the Broadcom ControlVault 2 reader (`USB ID 0a5c:5834`):
* **Dell Latitude:** 5591, 5490, 5590, 5290, 5480, 5580, 5280, 7490, 7390, 7290, 7480, 7380, 7280, E7470, E7270, E5570, E5470
* **Dell Precision:** 3520, 3530, 5520, 7520, 7720
* Any machine where `lsusb` outputs:
  ```text
  Bus 001 Device 00X: ID 0a5c:5834 Broadcom Corp. 5880
  ```

---

## 🚀 Quickstart (Build & Install)

### 1. Clone the repository
```bash
git clone https://github.com/<your-username>/dell-controlvault2-linux-driver.git
cd dell-controlvault2-linux-driver
```

### 2. Build the patched driver
This fetches the stock OEM Broadcom driver, verifies its SHA-256 hash, applies the 7 CV2 patches, and extracts the Citadel firmware:
```bash
./build_from_upstream.sh
```

### 3. Install
```bash
sudo ./install.sh
```

The installer will automatically:
* Install the patched driver into your system's TOD directory (`/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/`).
* Deploy the Broadcom Citadel firmware files to `/var/lib/fprint/fw/`.
* Configure the hardware udev rule (`61-broadcom-cv2-5834.rules`).
* Configure the Polkit security policy (`50-fprintd.rules`) requiring administrator authentication for enrollments (`AUTH_ADMIN`).
* **Pin TOD packages (`apt-mark hold`):** Automatically prevents Debian/Kali/Ubuntu `apt upgrade` or `fix-broken` from accidentally overwriting TOD packages with non-TOD distro versions.
* Unmask and restart `fprintd.service`.

---

## 🖐️ Usage & Enrollment

### 1. Enroll your fingerprint
```bash
fprintd-enroll
```
*(Enter your administrator password when prompted by Polkit, then touch and lift your finger 5 times until `enroll-completed`).*

### 2. Verify recognition
```bash
fprintd-verify
```

### 3. Enable fingerprint for `sudo` and Desktop Login
```bash
sudo pam-auth-update
```
Select `[*] Fingerprint authentication`, press **Tab** to `<Ok>`, and hit **Enter**.

---

## 🔒 APT Package Protection (`apt-mark hold`)

Debian and Kali Linux build stock `libfprint` packages without Touch OEM Device (TOD) support. During system upgrades (`sudo apt upgrade` or `sudo apt --fix-broken install`), `apt` may attempt to upgrade `libfprint-2-2` to the stock distro version and remove `libfprint-2-tod1`.

To permanently prevent this, `install.sh` automatically locks the TOD packages:
```bash
sudo apt-mark hold libfprint-2-tod1 libfprint-2-2
```
If you ever want to check the status or unhold them:
```bash
# Check status:
apt-mark showhold

# Release hold (unhold):
sudo apt-mark unhold libfprint-2-tod1 libfprint-2-2
```

---

## 🔬 How It Works (The 7 Binary Patches)

Dell and Canonical provide an official Touch OEM Device (TOD) driver for **ControlVault 3 (`0a5c:5842`)**. Because CV2 and CV3 share the same underlying Broadcom USH/Citadel architecture, `tools/patch_driver.py` modifies the binary byte-for-byte to drive CV2 sensors:

| Patch | Target | Description |
| :---: | :--- | :--- |
| **1** | `id_table` | Matches PID `0x5834` (was `0x5842`) so `libfprint` binds our device. |
| **2** | USB Enumerator | Bypasses PID filter (replaces `je` with `jmp`). |
| **3** | `dev_probe` | Treats error `0x1c` ("unknown chip") as success because CV2 uses resident ROM firmware. |
| **4** | Enroll State Machine | Maps CV2 status `0x59` ("data ready") to the template commit phase. |
| **5** | Verify Report | Drops the `edx!=0` short-circuit so non-zero verify status reports accurately. |
| **6** | Commit Wrapper | **Fixes Stage 5 Failure (Status 0x24):** Injects Dell CV2 `BroadcomWBF` identity structure into `cv_fingerprint_commit_enrollment`. |
| **7** | Identity Storage | Stores the 29-byte identity struct inside an unused debug log string in the binary. |

Full technical analysis and disassembly offsets are detailed in **[tools/PATCHES.md](tools/PATCHES.md)**.

---

## 🔍 Diagnostics

Run the read-only diagnostic utility at any time to verify hardware, kernel modules, driver installation, package holds, and daemon status:
```bash
./verify.sh
```

---

## 🛡️ Security & Polkit Policy

By default, `/etc/polkit-1/rules.d/50-fprintd.rules` requires administrative (`root` / `sudo`) authorization before enrolling any new fingerprint:
```javascript
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("net.reactivated.fprint.device.enroll") === 0) {
        return polkit.Result.AUTH_ADMIN;
    }
});
```

---

## 🗑️ Uninstallation

To cleanly remove the driver, firmware, and release package holds:
```bash
sudo ./uninstall.sh
```

---

## 📄 License

This repository is licensed under the [MIT License](LICENSE).  
Proprietary driver binaries and firmware blobs fetched at build time remain the intellectual property of Dell Technologies, Broadcom Inc., and Canonical Ltd.
