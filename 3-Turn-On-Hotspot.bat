@echo off
title Nothing Connect // Remote Hotspot
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0core\Hotspot.ps1"
exit
