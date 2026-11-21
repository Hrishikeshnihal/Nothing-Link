# Nothing Link

[![Release](https://img.shields.io/github/v/release/Hrishikeshnihal/Nothing-Link?color=D71921)](https://github.com/Hrishikeshnihal/Nothing-Link/releases/tag/v3.0.0-PRO)
[![Nothing OS](https://img.shields.io/badge/Nothing_OS-5.0-black)](https://github.com/Hrishikeshnihal/Nothing-Link)
[![Companion APK](https://img.shields.io/badge/Download-APK-34D399)](https://github.com/Hrishikeshnihal/Nothing-Link/releases/download/v3.0.0-PRO/nothing-connect-companion.apk)

A high-performance wireless screen mirroring and remote control system tailored for Nothing OS devices.

### 📥 [Download Latest Release v3.0.0-PRO](https://github.com/Hrishikeshnihal/Nothing-Link/releases/tag/v3.0.0-PRO)

## Features

- **Screen Off Mirroring**: Mirrors display to PC while keeping the physical phone display completely turned off to stay cool and save battery (`--turn-screen-off --stay-awake --power-off-on-close`).
- **120 FPS High Refresh Rate**: Streams low-latency video using hardware H.265 encoding over local Wi-Fi Hotspot or USB.
- **Automated Lockscreen Unlock**: Wakes screen, brings up bouncer, and inputs pattern `159873` hands-free upon launching.
- **Remote Hotspot Control**: Enables the phone's Wi-Fi hotspot remotely via cloud commands and Shizuku shell.
- **Portable Host Engine**: Preconfigured portable ADB and Scrcpy runtime included in `bin/`—no SDK installation required on PC.

## Quick Start

### 1. Initial Setup
1. Connect your phone to your PC via USB cable.
2. Enable **USB Debugging** under *Settings -> System -> Developer Options*.
3. Run `Setup.bat` to install the companion APK, grant permissions, and configure wireless ADB port 5555.

### 2. Daily Wireless Usage
1. Turn ON the Wi-Fi Hotspot on your phone.
2. Connect your PC Wi-Fi to your phone's hotspot.
3. Run `1-Mirror-Screen.bat`. The script auto-detects the gateway IP, performs the unlock sequence, and starts 120 FPS mirroring with the phone display powered off.

## Launchers

- `Setup.bat`: One-click setup for new PCs (installs APK, grants permissions, starts services).
- `1-Mirror-Screen.bat`: Connects over hotspot, auto-unlocks, and streams with phone display OFF.
- `2-Mirror-Screen-On.bat`: Streams while keeping the physical phone screen visible.
- `3-Turn-On-Hotspot.bat`: Sends remote command to activate phone hotspot.
- `Start-Nothing-Link.bat`: Opens local Web Dashboard at `http://localhost:3000`.
- `Start-Shizuku.bat`: Starts Shizuku server on phone via ADB after a reboot.
- `Install-Companion-App.bat`: Installs or updates the companion APK to connected phone.

## Configuration

Settings can be customized in `settings.ini`:

```ini
[Network]
WirelessIp=10.38.115.80
HotspotSsid=Nothing phone (2a) Plus

[Display]
MaxFps=120
VideoCodec=h265

[Security]
Pattern=159873
```

## Project Structure

```text
├── 1-Mirror-Screen.bat         # Mirror with screen off & auto-unlock
├── 2-Mirror-Screen-On.bat      # Mirror with screen visible
├── 3-Turn-On-Hotspot.bat       # Remote hotspot activation
├── Setup.bat                   # Automated setup script
├── Start-Nothing-Link.bat      # Web dashboard launcher
├── Start-Shizuku.bat           # ADB Shizuku starter
├── Install-Companion-App.bat   # APK installer
├── settings.ini                # Runtime configuration
├── android-companion/          # Android companion app source code
├── bin/scrcpy/                 # Portable ADB and Scrcpy binaries
├── companion/                  # Precompiled companion APK
├── core/                       # Automation scripts (PowerShell & Shell)
└── server/                     # Web dashboard server
```
