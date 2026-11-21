@echo off
title Nothing Connect // Hotspot Mirror (120 FPS)
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0core\Hotspot-Connect.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Press any key to close...
    pause >nul
)
exit /b %ERRORLEVEL%
