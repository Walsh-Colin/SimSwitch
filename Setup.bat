@echo off
setlocal
set "setupPowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "setupPowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%setupPowerShell%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\Setup-SimSwitch.ps1" %*
set "setupExit=%errorlevel%"
if not "%setupExit%"=="0" (
    echo.
    echo Setup failed. See the error above and logs\SimSwitch.log for details.
    pause
)
exit /b %setupExit%
