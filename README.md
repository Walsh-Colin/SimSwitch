# SimSwitch

Switch between your **Desktop** and **Sim rig** monitor setups from the Windows system tray. Choose enabled monitors, primary display, resolution and refresh rate separately for each setup.

## First-time setup

1. Download and extract this repository, or clone it, into a folder you plan to keep.
2. Enable all your monitors in Windows Display Settings for the initial configuration.
3. Double-click **`Setup.bat`**. It creates the local folders, installs startup for your Windows account, starts the tray app, and opens Monitor settings.
4. Use **Identify** to match the screens. Configure **Desktop**, then **Sim rig**, and click **Save both setups**.

Windows PowerShell 5.1 and the built-in Windows desktop libraries are required. No administrator access, Git, Python or extra packages are needed to run the app. Setup does not change your monitor layout. Rerunning it preserves your saved setups and updates the startup shortcut if you moved the folder.

## Everyday use

- **Left-click the tray icon:** switch between your saved setups without opening settings.
- **Right-click the tray icon:** choose a setup, open settings, or exit.
- **`Open-Monitor-Settings.bat`:** edit monitors, primary display, resolution and Hz.
- **`Toggle-Monitors.bat`:** switch from a shortcut or command line.

In settings, **Apply selection** gives you 20 seconds to keep the change before reverting. Tray switches verify the result and attempt to restore the previous layout if switching fails.

## Local files

`data/` and `logs/` are created automatically and ignored by Git:

- `data/monitor-setups.json`: your two saved setups, including physical monitor identities. Created when you click **Save both setups**.
- `data/monitor-modes.json`: cached display modes. Created when applying a layout.
- `logs/`: diagnostics and errors. Created as needed.

Every PC needs its own monitor configuration. A fresh checkout opens with the current screens selected as an editable starting point. Local editor settings, Windows shortcuts, temporary files and environment files are also ignored. Your existing local files are kept.

For startup removal, diagnostics and the complete usage guide, see [README.txt](README.txt).

## Development checks

Run from Windows PowerShell in the repository folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-First-Run.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Monitor-Restore.ps1
```

The first-run test uses an isolated copy and a test Startup folder. The restoration test uses a simulated display API. Neither test changes your screens or installs startup for your account.
