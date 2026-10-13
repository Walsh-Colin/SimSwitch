@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Toggle-Monitors.ps1" %*
if errorlevel 1 pause
