# Tests a clean download without changing screens or the real Startup folder.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('SimSwitch First Run & Test-' + [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $testRoot 'Fresh download'
$startupFolder = Join-Path $testRoot 'Test Startup'
$null = [IO.Directory]::CreateDirectory($packageRoot)
Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts') -Destination $packageRoot -Recurse
Copy-Item -LiteralPath (Join-Path $projectRoot 'Setup.bat') -Destination $packageRoot

function Invoke-TestSetup([string]$Folder) {
    # Exercise the batch entry point too, including spaces and & in its path.
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $info.Arguments = '/d /s /c ""' + (Join-Path $Folder 'Setup.bat') + '" -NoLaunch -StartupFolder "' + $startupFolder + '""'
    $info.WorkingDirectory = $testRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    try {
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { throw 'Setup did not finish within 30 seconds.' }
        if ($process.ExitCode -ne 0) { throw ('Setup failed: ' + $output.Result + $errors.Result) }
    } finally { $process.Dispose() }
}

function Assert-TestShortcut([string]$Folder) {
    $shell = $null
    $shortcut = $null
    try {
        $shortcutPath = Join-Path $startupFolder 'SimSwitch.lnk'
        if (-not (Test-Path -LiteralPath $shortcutPath)) { throw 'Startup shortcut was not created.' }
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $expectedScript = Join-Path $Folder 'scripts\Monitor-Tray.ps1'
        if ($shortcut.TargetPath -ne (Join-Path $PSHOME 'powershell.exe')) { throw 'Shortcut uses the wrong PowerShell executable.' }
        if (-not $shortcut.Arguments.Contains('"' + $expectedScript + '"') -or $shortcut.Arguments -notmatch '-STA .*?-WindowStyle Hidden') { throw 'Shortcut must launch the tray script hidden with STA.' }
        if ($shortcut.WorkingDirectory -ne $Folder) { throw 'Shortcut has an incorrect working directory.' }
    } finally {
        if ($shortcut) { $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
        if ($shell) { $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    }
}

try {
    Invoke-TestSetup $packageRoot
    foreach ($folder in 'data','logs') {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $folder) -PathType Container)) { throw "Setup did not create $folder." }
    }
    Assert-TestShortcut $packageRoot
    $entries = @(Get-Content -LiteralPath (Join-Path $packageRoot 'logs\SimSwitch.log') | ForEach-Object { $_ | ConvertFrom-Json })
    if (-not @($entries | Where-Object Event -eq 'Setup completed').Count) { throw 'Setup completion was not logged.' }
    $presetPath = Join-Path $packageRoot 'data\monitor-setups.json'
    if (Test-Path -LiteralPath $presetPath) { throw 'Setup should let the user choose monitors before saving presets.' }
    'Fresh batch setup, generated folders, startup shortcut and logging: passed'

    '{"Desktop":{"Names":["test-desktop"],"Primary":"test-desktop"},"Sim rig":{"Names":["test-rig"],"Primary":"test-rig"}}' | Set-Content -LiteralPath $presetPath -Encoding UTF8
    $before = (Get-FileHash -LiteralPath $presetPath).Hash
    Invoke-TestSetup $packageRoot
    Assert-TestShortcut $packageRoot
    if ((Get-FileHash -LiteralPath $presetPath).Hash -ne $before) { throw 'Rerunning setup changed existing presets.' }
    if (@(Get-ChildItem -LiteralPath $startupFolder -Filter *.lnk).Count -ne 1) { throw 'Rerunning setup created duplicate shortcuts.' }
    'Repeat setup preserves presets and updates one shortcut: passed'

    # Copy instead of moving so every test input remains available on failure.
    $relocatedRoot = Join-Path $testRoot 'Relocated download'
    Copy-Item -LiteralPath $packageRoot -Destination $relocatedRoot -Recurse
    Invoke-TestSetup $relocatedRoot
    Assert-TestShortcut $relocatedRoot
    if ((Get-FileHash -LiteralPath (Join-Path $relocatedRoot 'data\monitor-setups.json')).Hash -ne $before) { throw 'Relocation setup changed saved presets.' }
    'Setup repairs the startup path after relocating the folder: passed'

    # Saving modes and logging must also work without running Setup first.
    $directRoot = Join-Path $testRoot 'Direct launch'
    $null = [IO.Directory]::CreateDirectory($directRoot)
    Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts') -Destination $directRoot -Recurse
    & {
        $script:MonitorLogPath = $null
        . (Join-Path $directRoot 'scripts\Monitor-Layout.ps1')
        Write-MonitorLog 'First log entry' @{Test=$true}
        Save-ActiveModes @()
    }
    if (-not (Test-Path -LiteralPath (Join-Path $directRoot 'logs\SimSwitch.log'))) { throw 'Logging did not create its directory.' }
    $cache = Get-Content -LiteralPath (Join-Path $directRoot 'data\monitor-modes.json') -Raw | ConvertFrom-Json
    if (@($cache.PSObject.Properties).Count -ne 0) { throw 'An empty layout should create an empty mode cache.' }
    'Direct use creates missing logs and mode-cache folders: passed'

    # Delete only this test's allocated directory, after checking its location.
    $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedTestRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolvedTestRoot -Leaf) -notlike 'SimSwitch First Run & Test-*') { throw 'Test cleanup path was outside the allocated temporary directory.' }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
} catch {
    Write-Host "Test files retained for inspection: $testRoot"
    throw
}
