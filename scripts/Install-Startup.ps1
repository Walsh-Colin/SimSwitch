param([string]$StartupFolder = [Environment]::GetFolderPath('Startup'))
$ErrorActionPreference = 'Stop'
$trayScript = Join-Path $PSScriptRoot 'Monitor-Tray.ps1'
if (-not (Test-Path -LiteralPath $trayScript)) {
    throw "Tray script not found: $trayScript"
}
if ([string]::IsNullOrWhiteSpace($StartupFolder)) { throw 'Windows did not provide a Startup folder for this account.' }
$null = [IO.Directory]::CreateDirectory($StartupFolder)
$shortcutPath = Join-Path $StartupFolder 'SimSwitch.lnk'
$shell = $null
$shortcut = $null
try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $PSHOME 'powershell.exe'
    $shortcut.Arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $trayScript + '"'
    $shortcut.WorkingDirectory = Split-Path $PSScriptRoot -Parent
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'Start the SimSwitch monitor tray at sign-in'
    $shortcut.Save()
} finally {
    if ($shortcut) { $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    if ($shell) { $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}
Write-Output "Installed startup shortcut: $shortcutPath"
