@echo off
title Nothing Link Launcher
cd /d "%~dp0\server"

:: Check if server is already running on port 3000
netstat -ano | findstr ":3000" | findstr "LISTENING" >nul
if %errorlevel% neq 0 (
    echo Starting Nothing Link Cloud Server...
    start "" /B node server.js
    timeout /t 1 /nobreak >nul
)

:: Launch Microsoft Edge in app mode
start msedge.exe --app="http://localhost:3000" --window-size=960,820

exit /b 0
