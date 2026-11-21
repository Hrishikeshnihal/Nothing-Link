@echo off
title Nothing Link // One-Click Setup & Installer
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ===================================================================
echo              NOTHING LINK // ONE-CLICK SETUP ^& INSTALLER
echo ===================================================================
echo.

set "ADB=%~dp0bin\scrcpy\adb.exe"
set "APK=%~dp0companion\nothing-connect-companion.apk"

:: 1. Verify Bundled Binaries & Companion APK
echo [1/4] Verifying Scrcpy Engine ^& Companion APK...
if not exist "%ADB%" (
    echo       Downloading portable Scrcpy v3.3.4 ^& ADB engine...
    if not exist "%~dp0bin\scrcpy" mkdir "%~dp0bin\scrcpy"
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $z = Join-Path $env:TEMP 'scrcpy.zip'; Invoke-WebRequest -Uri 'https://github.com/Genymobile/scrcpy/releases/download/v3.3.4/scrcpy-win64-v3.3.4.zip' -OutFile $z; Expand-Archive -Path $z -DestinationPath (Join-Path $env:TEMP 'scrcpy_ext') -Force; Copy-Item -Path (Join-Path (Join-Path $env:TEMP 'scrcpy_ext') 'scrcpy-win64-v3.3.4\*') -Destination '%~dp0bin\scrcpy' -Recurse -Force; Remove-Item $z -Force; Remove-Item (Join-Path $env:TEMP 'scrcpy_ext') -Recurse -Force" >nul 2>&1
)
if not exist "%APK%" (
    echo       Downloading Nothing Link Companion APK from GitHub Releases...
    if not exist "%~dp0companion" mkdir "%~dp0companion"
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/Hrishikeshnihal/Nothing-Link/releases/download/v3.0.0-PRO/nothing-connect-companion.apk' -OutFile '%APK%'" >nul 2>&1
)
echo       Scrcpy v3.3.4 runtime ^& Companion APK ready. OK.
echo.

:: 2. Setup Node.js Cloud Server Dependencies (Optional)
echo [2/4] Checking Node.js for Cloud Dashboard...
where node >nul 2>&1
if %errorlevel% equ 0 (
    echo       Node.js detected. Installing server dependencies...
    if exist "server\package.json" (
        cd /d "%~dp0server"
        call npm install --silent >nul 2>&1
        cd /d "%~dp0"
        echo       Server dependencies ready. OK.
    )
) else (
    echo       Node.js not detected (optional for Web Dashboard).
    echo       Native BAT files (1-Mirror-Screen.bat) will work directly.
)
echo.

:: 3. Phone Detection & Companion App Installation
echo [3/4] Detecting Nothing Phone via USB...
echo       Please ensure:
echo         1. Phone is plugged into PC via USB cable.
echo         2. USB Debugging is ENABLED in Developer Options.
echo         3. If prompted on phone, tap 'Always Allow from this computer'.
echo.

set "PHONE_ID="
for /f "tokens=1,2" %%A in ('"%ADB%" devices') do (
    if "%%B"=="device" (
        set "PHONE_ID=%%A"
    )
)

if "%PHONE_ID%"=="" (
    echo [NOTICE] No phone detected via USB right now.
    echo.
    echo You can install the companion app later by plugging in USB and
    echo running 'Setup.bat' or 'Install-Companion-App.bat', OR by
    echo copying 'companion\nothing-connect-companion.apk' directly to your phone.
    echo.
) else (
    echo       Found phone: %PHONE_ID%
    echo       Installing Nothing Link Companion APK...
    "%ADB%" -s %PHONE_ID% install -r -d "%APK%" >nul 2>&1
    
    echo       Granting permissions...
    "%ADB%" -s %PHONE_ID% shell "pm grant com.nothing.link.companion android.permission.POST_NOTIFICATIONS 2>/dev/null"
    "%ADB%" -s %PHONE_ID% shell "pm grant com.nothing.link.companion moe.shizuku.manager.permission.API_V23 2>/dev/null"
    "%ADB%" -s %PHONE_ID% shell "dumpsys deviceidle whitelist +com.nothing.link.companion 2>/dev/null"
    "%ADB%" -s %PHONE_ID% shell "settings put secure enabled_accessibility_services com.nothing.link.companion/com.nothing.link.companion.service.NothingAccessibilityService 2>/dev/null"
    "%ADB%" -s %PHONE_ID% shell "settings put secure accessibility_enabled 1 2>/dev/null"
    "%ADB%" -s %PHONE_ID% shell "pm grant com.nothing.link.companion.debug android.permission.POST_NOTIFICATIONS 2>/dev/null"
    "%ADB%" -s %PHONE_ID% shell "pm grant com.nothing.link.companion.debug moe.shizuku.manager.permission.API_V23 2>/dev/null"
    "%ADB%" -s %PHONE_ID% shell "dumpsys deviceidle whitelist +com.nothing.link.companion.debug 2>/dev/null"

    echo       Starting Shizuku Service via ADB...
    "%ADB%" -s %PHONE_ID% shell "p=$(pm path moe.shizuku.privileged.api | head -n 1 | cut -d: -f2); d=$(dirname \"$p\"); if [ -f \"$d/lib/arm64/libshizuku.so\" ]; then \"$d/lib/arm64/libshizuku.so\"; elif [ -f \"$d/lib/arm/libshizuku.so\" ]; then \"$d/lib/arm/libshizuku.so\"; else sh /sdcard/Android/data/moe.shizuku.privileged.api/starter.sh; fi 2>/dev/null"

    echo       Enabling Wireless ADB Port 5555...
    "%ADB%" -s %PHONE_ID% tcpip 5555 >nul 2>&1

    echo       Launching Nothing Link on phone...
    "%ADB%" -s %PHONE_ID% shell "monkey -p com.nothing.link.companion -c android.intent.category.LAUNCHER 1 2>/dev/null"
    "%ADB%" -s %PHONE_ID% shell "monkey -p com.nothing.link.companion.debug -c android.intent.category.LAUNCHER 1 2>/dev/null"
    echo       Phone companion setup complete! OK.
)
echo.

:: 4. Optional Lock Screen Configuration
echo [4/4] Configuring Lock Screen Auto-Unlock...
echo.
echo Choose your Phone's Lock Screen Type:
echo   [1] Pattern (3x3 grid dots 1 to 9)
echo   [2] PIN (e.g. 1234)
echo   [3] Password (alphanumeric)
echo   [4] None / Swipe
echo   [Enter] Keep existing settings.ini
echo.
set /p "LOCK_CHOICE=Enter choice (1-4, or press Enter to skip): "

if "%LOCK_CHOICE%"=="1" (
    echo.
    echo Pattern Grid Reference:
    echo   1  2  3
    echo   4  5  6
    echo   7  8  9
    set /p "USER_PATTERN=Enter your pattern dot sequence (e.g. 159873 or 12359): "
    if not "!USER_PATTERN!"=="" (
        powershell -NoProfile -Command "(Get-Content '%~dp0settings.ini') -replace '^LockType=.*', 'LockType=pattern' -replace '^Pattern=.*', 'Pattern=!USER_PATTERN!' | Set-Content '%~dp0settings.ini'"
        echo Saved pattern to settings.ini.
    )
)
if "%LOCK_CHOICE%"=="2" (
    set /p "USER_PIN=Enter your lockscreen PIN: "
    if not "!USER_PIN!"=="" (
        powershell -NoProfile -Command "(Get-Content '%~dp0settings.ini') -replace '^LockType=.*', 'LockType=pin' -replace '^LockCode=.*', 'LockCode=!USER_PIN!' | Set-Content '%~dp0settings.ini'"
        echo Saved PIN to settings.ini.
    )
)
if "%LOCK_CHOICE%"=="3" (
    set /p "USER_PWD=Enter your lockscreen password: "
    if not "!USER_PWD!"=="" (
        powershell -NoProfile -Command "(Get-Content '%~dp0settings.ini') -replace '^LockType=.*', 'LockType=password' -replace '^LockCode=.*', 'LockCode=!USER_PWD!' | Set-Content '%~dp0settings.ini'"
        echo Saved password to settings.ini.
    )
)
if "%LOCK_CHOICE%"=="4" (
    powershell -NoProfile -Command "(Get-Content '%~dp0settings.ini') -replace '^LockType=.*', 'LockType=none' | Set-Content '%~dp0settings.ini'"
    echo Set Auto-Unlock to None/Swipe.
)
echo.

:: Done Summary
echo ===================================================================
echo                      SETUP COMPLETED!
echo ===================================================================
echo.
echo HOW TO USE:
echo   1. Turn ON your phone's Wi-Fi Hotspot.
echo   2. Connect PC Wi-Fi to your phone's Hotspot.
echo   3. Double-click '1-Mirror-Screen.bat' to start mirroring!
echo.
echo   - 1-Mirror-Screen.bat   : 120 FPS Mirror with screen OFF ^& auto-unlock
echo   - 2-Mirror-Screen-On.bat: Mirror with phone screen visible
echo   - 3-Turn-On-Hotspot.bat : Toggle phone hotspot remotely
echo   - Start-Shizuku.bat     : Restarts Shizuku anytime after phone reboot
echo   - Start-Nothing-Link.bat: Launches Cloud Dashboard (localhost:3000)
echo ===================================================================
echo.
pause
