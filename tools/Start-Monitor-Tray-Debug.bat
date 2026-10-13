@echo off
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0..\scripts\Monitor-Tray.ps1"
if errorlevel 1 pause
