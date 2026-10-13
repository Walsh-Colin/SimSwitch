. (Join-Path $PSScriptRoot 'Monitor-Native.ps1')
. (Join-Path $PSScriptRoot 'Monitor-Logging.ps1')
. (Join-Path $PSScriptRoot 'Monitor-Topology.ps1')
function Get-Layout {
    $identities=@{}
    foreach ($mapping in [MonitorTopology]::Mappings()) { $identities[$mapping.Name]=$mapping.Identity }
    $rows = foreach ($d in [MonitorSwitch]::Devices()) {
        $enabled = ($d.flags -band 1) -ne 0
        $mode = $null
        if ($enabled) { $mode = [MonitorSwitch]::Read($d.name, -1) }
        [pscustomobject]@{ Name=$d.name; Identity=$identities[$d.name]; Description=$d.description; Enabled=$enabled; Primary=(($d.flags -band 4) -ne 0); Mode=$mode }
    }
    return @($rows)
}
function Set-Layout($rows, [switch]$ValidateOnly, [switch]$Dynamic) {
    $enabled = @($rows | Where-Object Enabled)
    if ($enabled.Count -eq 0 -or @($enabled | Where-Object Primary).Count -ne 1) { throw 'Select at least one monitor and exactly one primary monitor.' }
    $devices = @([MonitorSwitch]::Devices())
    if ($ValidateOnly) { return $enabled }
    Write-MonitorLog 'Layout requested' $rows
    if (-not $Dynamic) {
        $requests=@(foreach ($row in @($enabled | Sort-Object Primary -Descending)) {
            $request=New-Object MonitorTopology+Request
            $request.Name=$row.Name; $request.Width=$row.Mode.width; $request.Height=$row.Mode.height
            $request.Identity=$row.Identity
            $request.Hz=$row.Mode.frequency; $request.X=$row.Mode.x; $request.Y=$row.Mode.y; $request.Primary=$row.Primary
            $request
        })
        $code=[MonitorTopology]::Configure([MonitorTopology+Request[]]$requests,$true)
        Write-MonitorLog 'Atomic topology validation' @{Code=$code;Stage=[MonitorTopology]::LastStage;Requests=$requests}
        if ($code -eq 0) {
            $code=[MonitorTopology]::Configure([MonitorTopology+Request[]]$requests,$false)
            Write-MonitorLog 'Atomic topology apply' @{Code=$code}
            if ($code -ne 0) { throw "Windows could not apply the complete monitor setup (code $code)." }
            return
        }
        # Older/virtual display drivers may not implement the modern API.
        if ($code -notin 50,31) { throw "Windows rejected the complete monitor setup (code $code)." }
        Write-MonitorLog 'Atomic topology unsupported; using legacy API' @{Code=$code}
    }
    $prepared=@()
    foreach ($row in $enabled) {
        if ($row.Name -notin $devices.name) { throw "Monitor not connected: $($row.Name)" }
        $m = [MonitorSwitch]::Resolve($row.Name,$row.Mode.width,$row.Mode.height,$row.Mode.frequency,$row.Mode.orientation,$row.Mode.displayFlags)
        $m.driverExtra=0; $m.fields = 0x5c0020
        $m.x=$row.Mode.x; $m.y=$row.Mode.y
        if ($m.width -eq 0 -or $m.height -eq 0) { throw "No saved resolution for $($row.Name). Enable it in Windows Display Settings first." }
        $prepared+=[pscustomobject]@{Name=$row.Name;Primary=$row.Primary;Mode=$m}
    }
    # Stage the new primary at the origin before moving the other monitors.
    $staged=0
    foreach ($row in @($prepared | Sort-Object Primary -Descending)) {
        $m=$row.Mode
        $flags = [uint32]0x10000001
        if ($Dynamic) { $flags=0; if ($row.Primary) { $flags=0x10 } }
        Write-MonitorLog 'Enable staging' @{ Device=$row.Name; Primary=$row.Primary; Mode=$m; Flags=$flags }
        $result = [MonitorSwitch]::ChangeDisplaySettingsEx($row.Name, [ref]$m, [IntPtr]::Zero, $flags, [IntPtr]::Zero)
        Write-MonitorLog 'Enable result' @{Device=$row.Name;Code=$result}
        if ($result -eq -1 -and -not $Dynamic -and $staged -eq 0) {
            Write-MonitorLog 'Registry staging rejected; trying dynamic layout' @{Device=$row.Name;Code=$result}
            Set-Layout $rows -Dynamic
            return
        }
        if ($result -ne 0) { throw "Cannot enable $($row.Name) (code $result)." }
        $staged++
    }
    # Set primary in a separate position-only operation. Some display drivers
    # reject CDS_SET_PRIMARY when it also requests resolution / refresh fields.
    if (-not $Dynamic) {
    $primaryRow=$prepared | Where-Object Primary | Select-Object -First 1
    $m=$primaryRow.Mode; $m.fields=0x20; $m.x=0; $m.y=0
    Write-MonitorLog 'Primary staging' @{Device=$primaryRow.Name;Mode=$m}
    $result=[MonitorSwitch]::ChangeDisplaySettingsEx($primaryRow.Name,[ref]$m,[IntPtr]::Zero,0x10000011,[IntPtr]::Zero)
    Write-MonitorLog 'Primary result' @{Device=$primaryRow.Name;Code=$result}
    if ($result -ne 0) { throw "Cannot set $($primaryRow.Name) as primary (code $result)." }
    }
    foreach ($d in $devices) {
        if ($d.name -in $enabled.Name) { continue }
        if (($d.flags -band 1) -eq 0) { continue }
        $m = New-Object MonitorSwitch+Mode
        $m.size=220; $m.fields=0x180020
        Write-MonitorLog 'Disable staging' @{Device=$d.name;Mode=$m}
        $flags=if ($Dynamic) { [uint32]0 } else { [uint32]0x10000001 }
        $result = [MonitorSwitch]::ChangeDisplaySettingsEx($d.name,[ref]$m,[IntPtr]::Zero,$flags,[IntPtr]::Zero)
        Write-MonitorLog 'Disable result' @{Device=$d.name;Code=$result}
        if ($result -ne 0) { throw "Cannot disable $($d.name) (code $result)." }
    }
    if ($Dynamic) { return }
    $result = [MonitorSwitch]::ApplyAll()
    Write-MonitorLog 'Apply result' @{Code=$result}
    if ($result -ne 0) { throw "Cannot apply layout (code $result)." }
}
function Save-ActiveModes($rows) {
    $path = Join-Path (Split-Path $PSScriptRoot -Parent) 'data\monitor-modes.json'
    $null = [IO.Directory]::CreateDirectory((Split-Path $path -Parent))
    $cache = @{}
    if (Test-Path -LiteralPath $path) {
        $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        foreach ($p in $saved.PSObject.Properties) { $cache[$p.Name] = $p.Value }
    }
    foreach ($row in @($rows | Where-Object Enabled)) {
        $bytes = New-Object byte[] 220
        $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal(220)
        try {
            [Runtime.InteropServices.Marshal]::StructureToPtr($row.Mode,$ptr,$false)
            [Runtime.InteropServices.Marshal]::Copy($ptr,$bytes,0,220)
            $cache[$row.Name] = [Convert]::ToBase64String($bytes)
        } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr) }
    }
    $cache | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
}
function Convert-SetupToLayout($selection) {
    $selection=Resolve-Setup $selection
    if (-not $selection -or @($selection.Names).Count -eq 0 -or $selection.Primary -notin $selection.Names) { throw 'The saved setup needs enabled monitors and a primary monitor.' }
    $result=@(); $x=0; $offset=0
    foreach ($name in $selection.Names) {
        $choice=$null
        if ($selection.Modes) { $choice=if ($selection.Modes -is [System.Collections.IDictionary]) { $selection.Modes[$name] } else { $selection.Modes.PSObject.Properties[$name].Value } }
        if ($choice) {
            $modes=@([MonitorSwitch]::Modes($name) | Where-Object { "$($_.width) x $($_.height)" -eq $choice.Resolution -and [string]$_.frequency -eq [string]$choice.Hz })
            if ($modes.Count) { $m=$modes | Sort-Object orientation,displayFlags | Select-Object -First 1 }
            else {
                # Inactive GDI sources can expose another monitor's old mode list.
                # Let the atomic API validate the saved physical target's mode.
                if ($choice.Resolution -notmatch '^(\d+) x (\d+)$' -or [int]$choice.Hz -le 0) { throw "Invalid saved mode for $name." }
                $m=New-Object MonitorSwitch+Mode
                $m.size=220; $m.bitsPerPixel=32; $m.width=[uint32]$Matches[1]; $m.height=[uint32]$Matches[2]; $m.frequency=[uint32]$choice.Hz
            }
        } else {
            $m=[MonitorSwitch]::Read($name,-1)
        }
        $m.x=$x; $m.y=0
        if ($name -eq $selection.Primary) { $offset=$x }
        $identity=$null
        if ($selection.Identities) { $identity=if ($selection.Identities -is [System.Collections.IDictionary]) { $selection.Identities[$name] } else { $selection.Identities.PSObject.Properties[$name].Value } }
        if (-not $identity) { $identity=([MonitorTopology]::Mappings() | Where-Object Name -eq $name | Select-Object -First 1).Identity }
        $result+=[pscustomobject]@{Name=$name;Identity=$identity;Enabled=$true;Primary=($name -eq $selection.Primary);Mode=$m}
        $x+=[int]$m.width
    }
    foreach ($row in $result) { $row.Mode.x-=$offset }
    return $result
}
function Resolve-Setup($selection) {
    if (-not $selection) { return $selection }
    $mappings=@([MonitorTopology]::Mappings())
    $active=@(Get-Layout | Where-Object Enabled)
    $names=@(); $modes=@{}; $ids=@{}; $primary=$selection.Primary
    foreach ($oldName in $selection.Names) {
        $identity=$null; $choice=$null
        if ($selection.Identities) { $identity=if ($selection.Identities -is [System.Collections.IDictionary]) { $selection.Identities[$oldName] } else { $selection.Identities.PSObject.Properties[$oldName].Value } }
        if ($selection.Modes) { $choice=if ($selection.Modes -is [System.Collections.IDictionary]) { $selection.Modes[$oldName] } else { $selection.Modes.PSObject.Properties[$oldName].Value } }
        $mapping=$null
        if ($identity) {
            $mapping=$mappings | Where-Object { $_.Identity -eq $identity -or $_.LegacyIdentity -eq $identity } | Select-Object -First 1
            if (-not $mapping) { throw "A monitor saved in this setup is disconnected (identity $identity)." }
        } else {
            # Migrate old configurations using an unambiguous active mode match.
            $matches=@($active | Where-Object { $choice -and "$($_.Mode.width) x $($_.Mode.height)" -eq $choice.Resolution -and [string]$_.Mode.frequency -eq [string]$choice.Hz })
            if ($matches.Count -eq 1) { $mapping=$mappings | Where-Object Name -eq $matches[0].Name | Select-Object -First 1 }
            if (-not $mapping) {
                $preferred=@($mappings | Where-Object { $choice -and "$($_.Width) x $($_.Height)" -eq $choice.Resolution -and [string]$_.Hz -eq [string]$choice.Hz })
                if ($preferred.Count -eq 1) { $mapping=$preferred[0] }
                if (-not $mapping) {
                    $preferred=@($mappings | Where-Object { $choice -and "$($_.Width) x $($_.Height)" -eq $choice.Resolution })
                    if ($preferred.Count -eq 1) { $mapping=$preferred[0] }
                }
            }
            if (-not $mapping) { $mapping=$mappings | Where-Object Name -eq $oldName | Select-Object -First 1 }
        }
        $name=if ($mapping) { $mapping.Name } else { $oldName }
        if ($name -in $names) { throw 'Two saved entries resolve to the same physical monitor. Identify the screens and save the setup again.' }
        $names+=$name
        if ($choice) { $modes[$name]=$choice }
        if ($mapping) { $ids[$name]=$mapping.Identity }
        if ($oldName -eq $selection.Primary) { $primary=$name }
    }
    return [pscustomobject]@{Names=$names;Primary=$primary;Modes=$modes;Identities=$ids}
}
function Assert-Layout($rows) {
    $wanted=@($rows | Where-Object Enabled)
    $last=@()
    for ($attempt=0; $attempt -lt 15; $attempt++) {
        $actual=@(Get-Layout | Where-Object Enabled)
        $problems=@()
        if ($actual.Count -ne $wanted.Count) { $problems+='Enabled monitor count differs.' }
        foreach ($row in $wanted) {
            $found=if ($row.Identity) { $actual | Where-Object Identity -eq $row.Identity | Select-Object -First 1 } else { $actual | Where-Object Name -eq $row.Name | Select-Object -First 1 }
            if (-not $found) { $problems+="$($row.Name) is not enabled."; continue }
            if ($found.Primary -ne $row.Primary) { $problems+="$($row.Name) primary setting differs." }
            foreach ($field in 'width','height','frequency','x','y') { if ($found.Mode.$field -ne $row.Mode.$field) { $problems+="$($row.Name) ${field}: requested $($row.Mode.$field), actual $($found.Mode.$field)." } }
        }
        if (-not $problems.Count) { Write-MonitorLog 'Layout verified' $actual; return }
        $last=$problems
        Start-Sleep -Milliseconds 200
    }
    Write-MonitorLog 'Layout verification failed' @{Problems=$last;Actual=$actual;Requested=$wanted}
    throw ('Windows did not apply the requested setup: ' + ($last -join ' '))
}
