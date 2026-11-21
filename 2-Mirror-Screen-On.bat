@echo off
title Nothing Connect // Mirror (Screen ON)
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0core\Engine.ps1" -Mode ScreenOn

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Press any key to close...
    pause >nul
)
exit /b %ERRORLEVEL%
