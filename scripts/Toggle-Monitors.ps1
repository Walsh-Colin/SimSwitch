param([switch]$List, [ValidateSet('Toggle','Gaming','Sim','Status')][string]$Mode = 'Toggle')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Monitor-Logging.ps1')
try {
. (Join-Path $PSScriptRoot 'Monitor-Layout.ps1')

$devices = @([MonitorSwitch]::Devices())
$buttonSetups=@{}
$presetPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'data\monitor-setups.json'
if (Test-Path -LiteralPath $presetPath) {
    $saved=Get-Content -LiteralPath $presetPath -Raw | ConvertFrom-Json
    foreach ($name in 'Sim rig','Desktop') {
        $property=$saved.PSObject.Properties[$name]
        if ($property) { $buttonSetups[$name]=$property.Value }
    }
}
function Get-AssignedStatus {
    $active=@(Get-Layout | Where-Object Enabled)
    $primaryDevice=$active | Where-Object Primary | Select-Object -First 1
    foreach ($entry in @(@{Name='Sim rig';Mode='Sim'},@{Name='Desktop';Mode='Gaming'})) {
        $setup=$buttonSetups[$entry.Name]
        if ($setup -and $setup.Identities) {
            $wanted=@($setup.Identities.PSObject.Properties | ForEach-Object Value)
            $primaryIdentity=$setup.Identities.PSObject.Properties[$setup.Primary].Value
            if ($active.Count -eq $wanted.Count -and @($active | Where-Object { $_.Identity -notin $wanted }).Count -eq 0 -and $primaryDevice.Identity -eq $primaryIdentity) { return $entry.Mode }
            continue
        }
        try { $setup=Resolve-Setup $setup } catch { continue }
        if ($setup -and $active.Count -eq @($setup.Names).Count -and @($active | Where-Object { $_.name -notin $setup.Names }).Count -eq 0 -and $primaryDevice.name -eq $setup.Primary) { return $entry.Mode }
    }
    return 'Other'
}
if ($Mode -eq 'Status') {
    if ($buttonSetups.Count) { Get-AssignedStatus; exit 0 }
    'Other'
    exit 0
}
if ($List) {
    $devices | Select-Object name, description, @{Name='Enabled';Expression={($_.flags -band 1) -ne 0}} | Format-Table -AutoSize
    exit 0
}
if ($buttonSetups.Count) {
    $name=if ($Mode -eq 'Sim') { 'Sim rig' } elseif ($Mode -eq 'Gaming') { 'Desktop' } elseif ((Get-AssignedStatus) -eq 'Gaming') { 'Sim rig' } else { 'Desktop' }
    if (-not $buttonSetups.ContainsKey($name)) { throw "Assign the $name button in Monitor settings first." }
    $requested=@(Convert-SetupToLayout $buttonSetups[$name])
    $transaction=Join-Path ([IO.Path]::GetTempPath()) ('SimSwitch-Tray-' + [Guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $transaction
    $requested | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $transaction 'requested.json')
    Write-MonitorLog 'Tray switch started' @{Button=$name;Folder=$transaction}
    & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Apply-Monitor-Layout.ps1') -Transaction $transaction -Commit
    $errorPath=Join-Path $transaction 'error.txt'
    if (Test-Path -LiteralPath $errorPath) { throw (Get-Content -LiteralPath $errorPath -Raw) }
    $donePath=Join-Path $transaction 'done'
    if (-not (Test-Path -LiteralPath $donePath) -or (Get-Content -LiteralPath $donePath -Raw).Trim() -ne 'Kept') { throw 'Monitor switching did not complete. Inspect SimSwitch.log.' }
    Write-Output "Switched to $name."
    exit 0
}
throw 'Configure Desktop and Sim rig in Monitor settings, then click Save both setups first.'
} catch {
    Write-MonitorError 'Toggle monitors' $_
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
