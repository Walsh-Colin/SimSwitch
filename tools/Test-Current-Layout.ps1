# Reapply the CURRENT layout and let the worker's countdown restore it.
# This exercises the real driver without choosing different screens or modes.
param([switch]$Diagnose, [switch]$TopologyValidate, [ValidateSet('Desktop','Sim rig')][string]$Setup)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\Monitor-Layout.ps1')
$before=@(Get-Layout)
if ($TopologyValidate) {
    $requests=@(foreach ($row in @($before | Where-Object Enabled | Sort-Object Primary -Descending)) {
        $request=New-Object MonitorTopology+Request
        $request.Name=$row.Name; $request.Width=$row.Mode.width; $request.Height=$row.Mode.height; $request.Hz=$row.Mode.frequency
        $request.Identity=$row.Identity
        $request.X=$row.Mode.x; $request.Y=$row.Mode.y; $request.Primary=$row.Primary
        $request
    })
    $code=[MonitorTopology]::Configure([MonitorTopology+Request[]]$requests,$true)
    Write-Output "Topology validation: $code at $([MonitorTopology]::LastStage)"
    Write-Output "Path bytes: $([Runtime.InteropServices.Marshal]::SizeOf([type][MonitorTopology+Path])); Mode bytes: $([Runtime.InteropServices.Marshal]::SizeOf([type][MonitorTopology+Mode]))"
    $saved=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\data\monitor-setups.json') -Raw | ConvertFrom-Json
    foreach ($name in 'Desktop','Sim rig') {
        $layout=@(Convert-SetupToLayout $saved.PSObject.Properties[$name].Value)
        $requests=@(foreach ($row in @($layout | Sort-Object Primary -Descending)) {
            $request=New-Object MonitorTopology+Request
            $request.Name=$row.Name; $request.Width=$row.Mode.width; $request.Height=$row.Mode.height; $request.Hz=$row.Mode.frequency
            $request.Identity=$row.Identity
            $request.X=$row.Mode.x; $request.Y=$row.Mode.y; $request.Primary=$row.Primary
            $request
        })
        $code=[MonitorTopology]::Configure([MonitorTopology+Request[]]$requests,$true)
        Write-Output "$name validation: $code at $([MonitorTopology]::LastStage)"
    }
    exit
}
if ($Diagnose) {
    foreach ($row in @($before | Where-Object Enabled)) {
        $m=[MonitorSwitch]::Read($row.Name,-1)
        Write-Output ($m | ConvertTo-Json -Compress)
        $result=[MonitorSwitch]::ChangeDisplaySettingsEx($row.Name,[ref]$m,[IntPtr]::Zero,0,[IntPtr]::Zero)
        Write-Output "Unchanged native mode, dynamic apply, $($row.Name): $result"
    }
    exit
}
$transaction=Join-Path ([IO.Path]::GetTempPath()) ('SimSwitch-Driver-Test-' + [Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $transaction
$requested=$before
if ($Setup) {
    $saved=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\data\monitor-setups.json') -Raw | ConvertFrom-Json
    $requested=@(Convert-SetupToLayout $saved.PSObject.Properties[$Setup].Value)
}
$requested | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $transaction 'requested.json')
& (Join-Path $PSScriptRoot '..\scripts\Apply-Monitor-Layout.ps1') -Transaction $transaction
$errorPath=Join-Path $transaction 'error.txt'
if (Test-Path -LiteralPath $errorPath) { throw (Get-Content -LiteralPath $errorPath -Raw) }
$outcome=(Get-Content -LiteralPath (Join-Path $transaction 'done') -Raw).Trim()
if ($outcome -ne 'Restored') { throw "Unexpected driver-test outcome: $outcome" }
Assert-Layout $before
'Real driver apply and automatic restoration passed; current layout preserved.'
