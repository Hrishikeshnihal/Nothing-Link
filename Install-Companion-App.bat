@echo off
title Nothing Link // Install Companion APK
setlocal
cd /d "%~dp0"

echo ======================================================
echo       NOTHING LINK // COMPANION APP INSTALLER         
echo ======================================================
echo.

set "ADB=%~dp0bin\scrcpy\adb.exe"
set "APK=%~dp0companion\nothing-connect-companion.apk"

if not exist "%APK%" (
    echo [1/3] Companion APK not found locally. Downloading from GitHub Releases...
    if not exist "%~dp0companion" mkdir "%~dp0companion"
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/Hrishikeshnihal/Nothing-Link/releases/download/v3.0.0-PRO/nothing-connect-companion.apk' -OutFile '%APK%'" >nul 2>&1
)

echo [1/3] Checking connected phone via ADB...
"%ADB%" devices

echo.
echo [2/3] Installing Nothing Link NOS 5.0 Companion to phone...
"%ADB%" install -r -d "%APK%"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ======================================================
    echo   SUCCESS! Nothing Link Companion is installed.
    echo.
    echo   Steps on phone:
    echo   1. Open 'Nothing Link' from your app drawer.
    echo   2. Grant Shizuku permission (for 1-tap Hotspot).
    echo   3. Enable Auto-Unlock Accessibility (for pattern 159873).
    echo ======================================================
    echo.
    echo [3/3] Launching Nothing Link on your phone...
    "%ADB%" shell monkey -p com.nothing.link.companion -c android.intent.category.LAUNCHER 1 >nul 2>&1
    "%ADB%" shell monkey -p com.nothing.link.companion.debug -c android.intent.category.LAUNCHER 1 >nul 2>&1
) else (
    echo.
    echo [NOTICE] If your phone is not connected via USB right now,
    echo you can also transfer the APK directly to your phone:
    echo %APK%
)

echo.
pause
