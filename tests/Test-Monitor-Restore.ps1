# Tests the real worker flow with a fake display API; never changes screens.
$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\scripts\Apply-Monitor-Layout.ps1') -Raw
$source=$source.Replace(". (Join-Path `$PSScriptRoot 'Monitor-Layout.ps1')",'')
$source=$source.Replace(". (Join-Path `$PSScriptRoot 'Monitor-Logging.ps1')",(Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\scripts\Monitor-Logging.ps1') -Raw))
$source=$source.Replace('Local\SimSwitchMonitorChange',('Local\SimSwitchMonitorTest-' + $PID))
$worker=[scriptblock]::Create($source)
function Get-Layout { [pscustomobject]@{Name='previous';Enabled=$true;Primary=$true} }
function Save-ActiveModes($rows) {}
function Assert-Layout($rows) {
    if ($script:scenario -eq 'VerificationFailure' -and @($rows)[0].Name -eq 'requested') { throw 'Simulated verification failure' }
}
function Set-Layout($rows) {
    if ($script:scenario -eq 'TwoMonitors' -and @($rows)[0].Name -eq 'requested' -and @($rows).Count -ne 2) { throw 'Monitor selection was nested or lost during JSON loading.' }
    $script:calls+=@($rows)[0].Name
    if (@($rows)[0].Name -eq 'requested') {
        switch ($script:scenario) {
            'Keep' { 'yes' | Set-Content -LiteralPath (Join-Path $script:testFolder 'keep') }
            'TwoMonitors' { 'yes' | Set-Content -LiteralPath (Join-Path $script:testFolder 'keep') }
            'Revert' { 'yes' | Set-Content -LiteralPath (Join-Path $script:testFolder 'revert') }
            'Failure' { throw 'Simulated display failure' }
        }
    }
}
foreach ($script:scenario in 'Keep','TwoMonitors','Commit','Revert','Failure','VerificationFailure','Timeout') {
    $script:testFolder=Join-Path ([IO.Path]::GetTempPath()) ('SimSwitch-Test-' + [Guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $script:testFolder
    $script:MonitorLogPath=Join-Path $script:testFolder 'test.log'
    '{"Name":"requested"}' | Set-Content -LiteralPath (Join-Path $script:testFolder 'requested.json')
    if ($script:scenario -eq 'TwoMonitors') { '[{"Name":"requested","Enabled":true,"Primary":true},{"Name":"second","Enabled":true,"Primary":false}]' | Set-Content -LiteralPath (Join-Path $script:testFolder 'requested.json') }
    $script:calls=@()
    & $worker -Transaction $script:testFolder -Commit:($script:scenario -eq 'Commit')
    $expected=if ($script:scenario -in 'Keep','TwoMonitors','Commit') { 'requested' } else { 'requested,previous' }
    if (($script:calls -join ',') -ne $expected) { throw "Failed $($script:scenario): $($script:calls -join ',')" }
    $outcome=(Get-Content -LiteralPath (Join-Path $script:testFolder 'done') -Raw).Trim()
    $expectedOutcome=if ($script:scenario -in 'Keep','TwoMonitors','Commit') { 'Kept' } else { 'Restored' }
    if ($outcome -ne $expectedOutcome) { throw "Unexpected outcome: $outcome" }
    if ($script:scenario -eq 'Failure' -and -not (Test-Path -LiteralPath (Join-Path $script:testFolder 'error.txt'))) { throw 'Failure was not logged.' }
    $entries=@(Get-Content -LiteralPath $script:MonitorLogPath | ForEach-Object { $_ | ConvertFrom-Json })
    if ($script:scenario -eq 'Failure' -and -not @($entries | Where-Object { $_.Event -eq 'Error' -and $_.Details.Message -eq 'Simulated display failure' }).Count) { throw 'Persistent log did not capture the exception.' }
    Write-Output "$($script:scenario): passed"
}
