@echo off
title Nothing Link // Start Shizuku Service
setlocal
cd /d "%~dp0"

echo ======================================================
echo           STARTING SHIZUKU SERVICE VIA ADB            
echo ======================================================
echo.

set "ADB=%~dp0bin\scrcpy\adb.exe"

echo [1/2] Checking connected device...
"%ADB%" devices

echo.
echo [2/2] Launching Shizuku server dynamically on phone...
"%ADB%" shell "p=$(pm path moe.shizuku.privileged.api | head -n 1 | cut -d: -f2); d=$(dirname \"$p\"); if [ -f \"$d/lib/arm64/libshizuku.so\" ]; then \"$d/lib/arm64/libshizuku.so\"; elif [ -f \"$d/lib/arm/libshizuku.so\" ]; then \"$d/lib/arm/libshizuku.so\"; else sh /sdcard/Android/data/moe.shizuku.privileged.api/starter.sh; fi"

echo.
echo ======================================================
echo   Shizuku service is now running!
echo ======================================================
echo.
pause
