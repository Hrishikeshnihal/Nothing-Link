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
    echo [ERROR] APK not found at: %APK%
    pause
    exit /b 1
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
