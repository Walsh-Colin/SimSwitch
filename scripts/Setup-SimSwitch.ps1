#Requires -Version 5.1
param(
    [switch]$NoLaunch,
    # Override only when testing installation in an isolated folder.
    [string]$StartupFolder = [Environment]::GetFolderPath('Startup')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Monitor-Logging.ps1')

function Start-SimSwitchApp([string]$ScriptName, [string]$MutexName) {
    $existing = $null
    $acquired = $false
    try {
        try { $existing = [Threading.Mutex]::OpenExisting($MutexName) }
        catch [Threading.WaitHandleCannotBeOpenedException] {}
        if ($existing) {
            try { $acquired = $existing.WaitOne(0) }
            catch [Threading.AbandonedMutexException] { $acquired = $true }
            if (-not $acquired) {
                Write-Host "$ScriptName is already running."
                return
            }
        }
    } finally {
        if ($acquired) { $existing.ReleaseMutex() }
        if ($existing) { $existing.Dispose() }
    }

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    $arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $scriptPath + '"'
    $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -ArgumentList $arguments -WorkingDirectory $projectRoot -PassThru
    try {
        if ($process.WaitForExit(1500) -and $process.ExitCode -ne 0) {
            throw "$ScriptName could not start. See logs\SimSwitch.log for details."
        }
    } finally { $process.Dispose() }
}

try {
    if ($PSVersionTable.PSEdition -ne 'Desktop') {
        throw 'Run Setup.bat using Windows PowerShell 5.1.'
    }
    Write-Host 'Setting up SimSwitch...'
    foreach ($folder in 'data','logs') {
        $null = [IO.Directory]::CreateDirectory((Join-Path $projectRoot $folder))
    }
    Write-MonitorLog 'Setup started' @{NoLaunch=[bool]$NoLaunch}

    # Check the package before installing its sign-in shortcut.
    foreach ($name in 'Install-Startup.ps1','Monitor-Tray.ps1','Monitor-Settings.ps1','Toggle-Monitors.ps1','Apply-Monitor-Layout.ps1','Monitor-Layout.ps1','Monitor-Native.ps1','Monitor-Topology.ps1','Monitor-Logging.ps1') {
        $path = Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing $name. Extract the complete SimSwitch download before running Setup.bat." }
        $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "Cannot load ${name}: $($parseErrors[0].Message)" }
    }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    & (Join-Path $PSScriptRoot 'Install-Startup.ps1') -StartupFolder $StartupFolder

    if (-not $NoLaunch) {
        Start-SimSwitchApp 'Monitor-Tray.ps1' 'Local\SimSwitchMonitorTray'
        Start-SimSwitchApp 'Monitor-Settings.ps1' 'Local\SimSwitchMonitorSettings'
    }
    Write-MonitorLog 'Setup completed' @{NoLaunch=[bool]$NoLaunch}
    Write-Host ''
    Write-Host 'Setup complete. SimSwitch will start automatically when you sign in.'
    Write-Host 'Enable all monitors in Windows Display Settings for the first configuration.'
    Write-Host 'In Monitor settings, configure Desktop and Sim rig, then click Save both setups.'
    Write-Host 'Existing saved setups are preserved. Rerun Setup.bat if you move this folder.'
    if ($NoLaunch) { Write-Host 'Open-Monitor-Settings.bat opens the configuration window when you are ready.' }
} catch {
    Write-MonitorError 'Setup failed' $_
    Write-Host ('Setup failed: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
