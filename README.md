# Nothing Link

[![Release](https://img.shields.io/github/v/release/Hrishikeshnihal/Nothing-Link?color=D71921)](https://github.com/Hrishikeshnihal/Nothing-Link/releases/tag/v3.0.0-PRO)
[![Nothing OS](https://img.shields.io/badge/Nothing_OS-5.0-black)](https://github.com/Hrishikeshnihal/Nothing-Link)
[![Companion APK](https://img.shields.io/badge/Download-APK-34D399)](https://github.com/Hrishikeshnihal/Nothing-Link/releases/download/v3.0.0-PRO/nothing-connect-companion.apk)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A high-performance wireless screen mirroring and remote control system tailored for Nothing OS devices.

### 📥 [Download Latest Release v3.0.0-PRO](https://github.com/Hrishikeshnihal/Nothing-Link/releases/tag/v3.0.0-PRO)

---

## ✨ Features

- **Screen Off Mirroring**: Mirrors display to PC while keeping the physical phone display completely turned off to stay cool and save battery (`--turn-screen-off --stay-awake --power-off-on-close`).
- **120 FPS High Refresh Rate**: Streams low-latency video using hardware H.265 encoding over local Wi-Fi Hotspot or USB.
- **Automated Lockscreen Unlock**: Wakes screen, brings up bouncer, and inputs pattern, PIN, or password hands-free upon launching.
- **Remote Hotspot Control**: Enables the phone's Wi-Fi hotspot remotely via cloud commands and Shizuku shell.
- **Portable Host Engine**: Preconfigured portable ADB and Scrcpy runtime included in `bin/`—no SDK installation required on PC.

---

## 🚀 Quick Start

### 1. Launch Nothing Link
Simply double-click **`NothingLink.exe`**.

### 2. First-Time Setup (1-Click)
1. Plug your Nothing Phone into your PC via USB cable (with USB Debugging enabled).
2. Click **`1-Click Setup`** inside the app.
3. The app automatically installs the companion APK, grants Shizuku and accessibility permissions, whitelists battery, and opens wireless ADB on port 5555.

### 3. Daily Wireless Usage
1. Connect your PC Wi-Fi to your phone's Wi-Fi Hotspot.
2. Open **`NothingLink.exe`** and click **`⚡ MIRROR (SCREEN OFF)`**.
3. The app automatically wakes and unlocks your phone (Pattern, PIN, Password, or Swipe) and starts 120 FPS hardware H.265 mirroring with the physical phone screen completely black.

---

## 🕹️ Shortcuts & Controls (Scrcpy Shortcuts)

| Shortcut (Default `Alt` / `MOD`) | Action |
|---|---|
| `MOD + f` | Toggle Fullscreen Mode |
| `MOD + h` | Go to Home Screen |
| `MOD + b` or Right-Click | Back |
| `MOD + s` | Open App Switcher / Recent Apps |
| `MOD + p` | Power On / Off Screen |
| `MOD + Shift + v` | Paste PC Clipboard into Phone |
| `MOD + n` | Expand Notification Panel |

---

## 🖥️ Nothing Link Windows Desktop App (`NothingLink.exe`)

The unified Windows program includes:
- **⚡ Mirror (Screen Off)**: 120 FPS LTPO streaming, hardware H.265 encoding, auto-unlocks, and keeps the physical phone screen black to stay cool and save battery.
- **📱 Mirror (Screen On)**: Streams while keeping the physical phone screen visible.
- **📶 Toggle Hotspot**: Sends remote command via Shizuku shell to toggle mobile hotspot on/off without touching your phone.
- **🛠️ 1-Click Setup**: Automatically installs the companion APK to connected phone, grants all necessary permissions, and configures wireless ADB port 5555.
- **⚡ Start Shizuku**: 1-click restarts the Shizuku server via ADB after a phone reboot.
- **🔒 Lock Screen Configuration**: Visual and instant setup for Pattern (3x3 grid), PIN, Password, or None.
- **🌐 Open Cloud Web Dashboard**: Launches the Web Cloud Dashboard on `http://localhost:3000`.

---

## ⚙️ Configuration

Settings can be customized in `settings.ini` or configured interactively during `Setup.bat`:

```ini
[Network]
WirelessIp=10.38.115.80
HotspotSsid=Nothing phone (2a) Plus

[Display]
MaxFps=120
VideoCodec=h265

[Security]
; Lock screen type: pattern, pin, password, or none
LockType=pattern

; If LockType=pin or LockType=password, enter your unlock PIN or password:
LockCode=1234

; If LockType=pattern, enter your 3x3 pattern sequence (digits 1 to 9):
; 1  2  3
; 4  5  6
; 7  8  9
Pattern=159873
```

---

## 🔧 Troubleshooting

| Issue | Resolution |
|---|---|
| **Device not detected over Wi-Fi** | Ensure both PC and Phone are on the same subnet/hotspot. Plug in USB and click `1-Click Setup` in NothingLink to re-enable wireless port 5555. |
| **Phone screen turns black & unresponsive** | Normal behavior during *Screen-Off Mirroring*. Press `MOD + p` or double-tap the phone power button to wake the physical display. |
| **Black screen or video lag** | In `settings.ini`, change `VideoCodec=h265` to `VideoCodec=h264`, or lower `MaxFps=120` to `MaxFps=60`. |
| **Shizuku service stopped** | If your phone was rebooted, click `Start Shizuku` inside `NothingLink.exe` to restart the Shizuku service over ADB. |

---

## 📁 Project Structure

```text
├── NothingLink.exe             # Unified Windows Desktop Program
├── settings.ini                # Runtime configuration (Network, Display, Security)
├── windows-app/                # Windows .NET 10 desktop application source code
├── android-companion/          # Android companion app source code (Nothing OS 5.0)
├── bin/scrcpy/                 # Portable ADB and Scrcpy runtime
├── companion/                  # Precompiled companion APK
├── core/                       # Core engine scripts (PowerShell & Shell)
└── server/                     # Web dashboard server
```

---

## 👤 Author

**Hrishikesh Nihal**
- GitHub: [@Hrishikeshnihal](https://github.com/Hrishikeshnihal)
- Email: nihalhrishikesh@gmail.com
