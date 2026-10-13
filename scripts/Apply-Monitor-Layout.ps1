param([Parameter(Mandatory=$true)][string]$Transaction, [switch]$Commit)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Monitor-Logging.ps1')
trap { Write-MonitorError 'Worker unhandled error' $_; exit 1 }
. (Join-Path $PSScriptRoot 'Monitor-Layout.ps1')
$layoutMutex=New-Object Threading.Mutex($false,'Local\SimSwitchMonitorChange')
$locked=$layoutMutex.WaitOne(0)
$restore = $false
$restoreSucceeded=$false
$applied=$false
try {
    Write-MonitorLog 'Transaction started' @{Folder=$Transaction}
    if (-not $locked) { throw 'Another monitor change is in progress. Try again after confirming or reverting it.' }
    $before = Get-Layout
    Write-MonitorLog 'Previous layout' $before
    $requested = Get-Content -LiteralPath (Join-Path $Transaction 'requested.json') -Raw | ConvertFrom-Json
    $before | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Transaction 'previous.json')
    Save-ActiveModes $before
    $restore = $true
    Set-Layout $requested
    Assert-Layout $requested
    $applied=$true
    if ($Commit) { Start-Sleep -Milliseconds 500; Assert-Layout $requested; $restore=$false; return }
    'Ready' | Set-Content -LiteralPath (Join-Path $Transaction 'ready')
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath (Join-Path $Transaction 'keep')) { $restore = $false; break }
        if (Test-Path -LiteralPath (Join-Path $Transaction 'revert')) { break }
        Start-Sleep -Milliseconds 200
    }
} catch {
    Write-MonitorError 'Apply transaction' $_
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $Transaction 'error.txt')
} finally {
    if ($restore) {
        Write-MonitorLog 'Restoring previous layout' @{Folder=$Transaction}
        try {
            Set-Layout $before
            Assert-Layout $before
            $restoreSucceeded=$true
            Write-MonitorLog 'Restore succeeded' @{Folder=$Transaction}
        } catch {
            Write-MonitorError 'Restore previous layout' $_
            $_ | Out-String | Add-Content -LiteralPath (Join-Path $Transaction 'error.txt')
        }
    }
    $outcome=if ($restoreSucceeded) { 'Restored' } elseif ($restore) { 'Restore failed' } elseif ($applied) { 'Kept' } else { 'Failed' }
    $outcome | Set-Content -LiteralPath (Join-Path $Transaction 'done')
    Write-MonitorLog 'Transaction finished' @{Folder=$Transaction;Outcome=$outcome;RestoreAttempted=$restore;RestoreSucceeded=$restoreSucceeded}
    if ($locked) { $layoutMutex.ReleaseMutex() }
    $layoutMutex.Dispose()
}
