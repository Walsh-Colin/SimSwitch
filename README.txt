SIMSWITCH

QUICK START
Setup.bat                 - First-time setup: folders, startup, tray and settings.
Open-Monitor-Settings.bat  - Edit Desktop and Sim rig monitor setups.
Start-Monitor-Tray.vbs     - Start the tray app without a console window.
Toggle-Monitors.bat       - Toggle between your saved Desktop and Sim rig setups.
Install-Startup.bat       - Start the tray app automatically at sign-in.

CONFIGURE YOUR TWO SETUPS
For initial setup, enable all monitors in Windows Display Settings first.
Extract the entire download into a folder you plan to keep, then double-click
Setup.bat. No administrator access or extra software installation is needed.
Setup creates the local folders, installs sign-in startup, starts the tray,
and opens settings. It does not switch screens or overwrite existing setups.
Open settings and use Identify to match the screens to the listed numbers.
Choose Desktop under Edit setup. Check the monitors you want on, select
resolution and Hz, and choose a primary using Set primary or the dropdown.
Choose Sim rig under Edit setup and configure its monitors the same way.
Your edits stay separate when switching between the two setup editors.
Click Save both setups to save the entire configuration in one operation.
Both setups must have at least one monitor and a primary among their enabled
monitors. An invalid setup prevents saving either setup.
Switch to Desktop / Switch to Sim rig uses the saved configuration.
Apply selection lets you try the currently edited selection before saving.
Changes to the editor alone do not change screens or overwrite saved setups.
Close and reopen settings and restart the tray app after updating SimSwitch.

APPLYING CHANGES
Selected screens are arranged left to right in list order, top aligned.
Click Keep changes within 20 seconds after applying a layout.
Revert, closing the window, or the timeout restores the previous layout.
The restore timer runs separately from the settings window.
Identify displays numbers on active screens for 4 seconds.
Refresh detects connected screens while preserving the current setup draft.

TRAY APP
Left-click the icon to toggle your saved Desktop and Sim rig setups.
Right-click to choose either setup, open settings, or Exit.
Orange steering wheel: Desktop. Blue controller: Sim rig.
Tray switches run in the background without opening settings or a countdown.
They verify the applied setup and restore the previous layout if switching fails.
Use the settings menu explicitly when you want to edit your setups.
Windows may hide the icon under the arrow beside the clock.

AUTOMATIC STARTUP
Setup.bat installs or updates SimSwitch.lnk in your Windows Startup folder.
Install-Startup.bat is available if you only want to update that shortcut.
Rerun Setup.bat after moving the project folder so the shortcut points to it.
To remove automatic startup, press Win+R, enter shell:startup, and delete
SimSwitch.lnk.

FOLDER LAYOUT
scripts\  - Application and startup installation scripts.
data\     - monitor-setups.json (Desktop and Sim rig), monitor-modes.json.
logs\     - SimSwitch.log and tray startup error details.
tests\    - Isolated first-run setup and simulated display restoration tests.
tools\    - Debug launcher and real-driver diagnostic tools.
data\ and logs\ are generated locally and ignored by Git. Save both setups
creates monitor-setups.json; applying a layout creates monitor-modes.json.
Each PC needs its own monitor assignments. Local editor settings, Windows
shortcuts, temporary files and environment files are also ignored by Git.

TROUBLESHOOTING
Click Open log to view logs\SimSwitch.log in Notepad.
The log includes layouts, modes, API return codes, exceptions, and restoration.
SimSwitch applies the complete monitor layout together through Windows display
configuration APIs, then checks which physical monitors, modes, and primary
screen are active. Saved setups use physical monitor device paths because
Windows DISPLAY numbers can change when screens are disabled or re-enabled.
The older display API remains a fallback for drivers without modern support.
Use tools\Start-Monitor-Tray-Debug.bat for a visible tray console.
To inspect device names, run Toggle-Monitors.bat -List.
Monitor numbers follow physical monitor identity order. Identify matches the
numbers in the settings grid. The Device column may change after a switch.
Windows disconnects unused screens rather than switching off physical power.
If screens go blank, try Win+P and choose Extend, or DisplaySwitch.exe /extend.
