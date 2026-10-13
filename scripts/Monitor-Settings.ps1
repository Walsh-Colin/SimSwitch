param([switch]$Check, [string]$PresetName, [switch]$ApplyPreset)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Monitor-Logging.ps1')
trap {
    Write-MonitorError 'Settings unhandled error' $_
    try { [Windows.Forms.MessageBox]::Show($_.Exception.Message + "`nDetails saved in SimSwitch.log",'SimSwitch error') | Out-Null } catch {}
    exit 1
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'Monitor-Layout.ps1')
$settingsMutex=New-Object Threading.Mutex($false,'Local\SimSwitchMonitorSettings')
if (-not $Check -and -not $settingsMutex.WaitOne(0)) {
    [Windows.Forms.MessageBox]::Show('Monitor settings is already open. Check your taskbar.','SimSwitch') | Out-Null
    $settingsMutex.Dispose()
    exit
}
[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'SimSwitch - Monitor settings'
$form.Size = New-Object Drawing.Size(760,610)
$form.MinimumSize = $form.Size
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI',10)
function Add-Control($type,$text,$x,$y,$w,$h) {
    $c = New-Object $type
    $c.Text=$text; $c.Location=New-Object Drawing.Point($x,$y); $c.Size=New-Object Drawing.Size($w,$h)
    $form.Controls.Add($c)
    return $c
}
$null = Add-Control Windows.Forms.Label 'Choose the monitors to keep on' 22 18 400 28
$identify = Add-Control Windows.Forms.Button 'Identify' 580 14 140 32
$openLog=Add-Control Windows.Forms.Button 'Open log' 430 14 140 32
$openLog.Add_Click({
    try {
        Write-MonitorLog 'Log opened' $null
        $info=New-Object Diagnostics.ProcessStartInfo
        $info.FileName=Join-Path $env:WINDIR 'System32\notepad.exe'
        $info.Arguments='"' + $script:MonitorLogPath + '"'
        $null=[Diagnostics.Process]::Start($info)
    } catch { Show-Error $_ }
})
$script:identifyWindows=@()
$identifyTimer=New-Object Windows.Forms.Timer
$identifyTimer.Interval=4000
function Close-Identify {
    $identifyTimer.Stop()
    foreach ($badge in $script:identifyWindows) {
        $badgeFont=$badge.Tag
        $badge.Close(); $badge.Dispose()
        $badgeFont.Dispose()
    }
    $script:identifyWindows=@()
}
function New-IdentifyBadge($screen) {
    $number=$screen.DeviceName
    for ($i=0; $i -lt $script:rows.Count; $i++) { if ($script:rows[$i].Name -eq $screen.DeviceName) { $number=[string]($i+1); break } }
    $badge=New-Object Windows.Forms.Form
    $badge.FormBorderStyle='None'; $badge.StartPosition='Manual'
    $badge.ShowInTaskbar=$false; $badge.TopMost=$true
    $badge.BackColor=[Drawing.Color]::FromArgb(35,45,65)
    $badge.ForeColor=[Drawing.Color]::White
    $width=[Math]::Min(340,$screen.Bounds.Width)
    $height=[Math]::Min(190,$screen.Bounds.Height)
    $badge.Size=New-Object Drawing.Size($width,$height)
    $badge.Location=New-Object Drawing.Point(($screen.Bounds.X+[int](($screen.Bounds.Width-$width)/2)),($screen.Bounds.Y+[int](($screen.Bounds.Height-$height)/2)))
    $label=New-Object Windows.Forms.Label
    $label.Dock='Fill'; $label.TextAlign='MiddleCenter'
    $badgeFont=New-Object Drawing.Font('Segoe UI',30,[Drawing.FontStyle]::Bold)
    $label.Font=$badgeFont; $badge.Tag=$badgeFont
    $label.Text="Monitor $number`n$($screen.DeviceName)"
    $badge.Controls.Add($label)
    return $badge
}
$identifyTimer.Add_Tick({ Close-Identify })
$identify.Add_Click({
    try {
        Close-Identify
        foreach ($screen in [Windows.Forms.Screen]::AllScreens) {
            $badge=New-IdentifyBadge $screen
            $script:identifyWindows+= $badge
            $badge.Show($form)
        }
        $identifyTimer.Start()
        if (-not $script:worker) { $status.Text='Numbers are shown on active screens for 4 seconds. Off monitors cannot display a number.' }
    } catch { Close-Identify; Show-Error $_ }
})
$null = Add-Control Windows.Forms.Label 'Selected monitors are arranged left to right in the order below.' 22 48 690 25
$grid = Add-Control Windows.Forms.DataGridView '' 22 82 698 205
$grid.AllowUserToAddRows=$false; $grid.AllowUserToDeleteRows=$false; $grid.RowHeadersVisible=$false
$grid.AutoSizeColumnsMode='Fill'; $grid.BackgroundColor=[Drawing.Color]::White
$on = New-Object Windows.Forms.DataGridViewCheckBoxColumn
$on.Name='On'; $on.HeaderText='On'; $on.FillWeight=20; $null=$grid.Columns.Add($on)
foreach ($name in 'Monitor','Device') {
    $col = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $col.Name=$name; $col.HeaderText=$name; $col.ReadOnly=$true
    $null=$grid.Columns.Add($col)
}
foreach ($name in 'Resolution','Hz') {
    $col=New-Object Windows.Forms.DataGridViewComboBoxColumn
    $col.Name=$name; $col.HeaderText=$name
    $col.DisplayStyle='DropDownButton'
    $null=$grid.Columns.Add($col)
}
$grid.EditMode='EditOnEnter'
$primaryColumn=New-Object Windows.Forms.DataGridViewButtonColumn
$primaryColumn.Name='SetPrimary'; $primaryColumn.HeaderText='Primary'
$primaryColumn.Text='Set primary'; $primaryColumn.UseColumnTextForButtonValue=$false
$null=$grid.Columns.Add($primaryColumn)
$grid.Add_CellContentClick({ param($sender,$e)
    if ($e.RowIndex -ge 0 -and $e.ColumnIndex -eq $grid.Columns['SetPrimary'].Index) {
        $grid.EndEdit() | Out-Null
        $grid.Rows[$e.RowIndex].Cells['On'].Value=$true
        $primary.SelectedItem=$script:rows[$e.RowIndex].Name
        $status.Text='Primary monitor selected. Click Apply selection, then Keep changes.'
    }
})
$script:modeOptions=@{}
$script:updatingModes=$false
function Update-Hz([int]$index, $preferred) {
    $row=$grid.Rows[$index]
    $resolution=[string]$row.Cells['Resolution'].Value
    $rates=@($script:modeOptions[$script:rows[$index].Name] | Where-Object { "$($_.width) x $($_.height)" -eq $resolution } | ForEach-Object { [int]$_.frequency } | Sort-Object -Unique)
    $cell=$row.Cells['Hz']
    $cell.Value=$null; $cell.Items.Clear()
    foreach ($rate in $rates) { $null=$cell.Items.Add([string]$rate) }
    if ($rates.Count) {
        $cell.Value=if ([int]$preferred -in $rates) { [string]$preferred } else { [string]$rates[-1] }
    }
}
$grid.Add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty) { $grid.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit) | Out-Null }
})
$grid.Add_CellValueChanged({ param($sender,$e)
    if (-not $script:updatingModes -and $e.RowIndex -ge 0 -and $e.ColumnIndex -eq $grid.Columns['Resolution'].Index) {
        $script:updatingModes=$true
        try { Update-Hz $e.RowIndex $grid.Rows[$e.RowIndex].Cells['Hz'].Value } finally { $script:updatingModes=$false }
    }
})
$grid.Add_DataError({ param($sender,$e) $e.ThrowException=$false; $status.Text='Choose a supported resolution and refresh rate for this monitor.' })
$null = Add-Control Windows.Forms.Label 'Primary monitor' 22 300 150 26
$primary = Add-Control Windows.Forms.ComboBox '' 180 298 385 30
$primary.DropDownStyle='DropDownList'
$primary.Add_SelectedIndexChanged({
    for ($i=0; $i -lt $grid.Rows.Count; $i++) {
        $grid.Rows[$i].Cells['SetPrimary'].Value=if ($script:rows[$i].Name -eq $primary.SelectedItem) { 'Primary' } else { 'Set primary' }
    }
})
$refresh = Add-Control Windows.Forms.Button 'Refresh' 580 297 140 32
$null = Add-Control Windows.Forms.Label 'Edit setup' 22 344 150 26
$setupSelector=Add-Control Windows.Forms.ComboBox '' 180 340 315 30
$setupSelector.DropDownStyle='DropDownList'
$null=$setupSelector.Items.Add('Desktop'); $null=$setupSelector.Items.Add('Sim rig')
$saveAll=Add-Control Windows.Forms.Button 'Save both setups' 510 338 210 34
$status = Add-Control Windows.Forms.Label 'Choose monitors, then apply. Changes revert unless you keep them.' 22 389 698 44
$apply = Add-Control Windows.Forms.Button 'Apply selection' 22 444 180 38
$keep = Add-Control Windows.Forms.Button 'Keep changes' 220 444 170 38
$revert = Add-Control Windows.Forms.Button 'Revert' 408 444 140 38
$deskButton=Add-Control Windows.Forms.Button 'Switch to Desktop' 22 500 220 38
$rigButton=Add-Control Windows.Forms.Button 'Switch to Sim rig' 260 500 220 38
$null=Add-Control Windows.Forms.Label 'Edit each setup above, then save both. Switch buttons use your saved setups.' 22 546 698 24
$keep.Enabled=$false; $revert.Enabled=$false
$script:transaction=$null; $script:worker=$null; $script:readyAt=$null
$presetPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'data\monitor-setups.json'
$script:saved=@{}
$script:setupDrafts=@{}
$script:editingSetup=$null
$script:selectingSetup=$false
if (Test-Path -LiteralPath $presetPath) {
    try {
        $data=Get-Content -LiteralPath $presetPath -Raw | ConvertFrom-Json
        foreach ($name in 'Desktop','Sim rig') { if ($data.PSObject.Properties[$name]) { $script:saved[$name]=$data.PSObject.Properties[$name].Value } }
    } catch { Write-MonitorError 'Read setups' $_; $status.Text='Could not read saved setups: ' + $_.Exception.Message }
}
function Refresh-Monitors {
    $known=@()
    $cachePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'data\monitor-modes.json'
    if (Test-Path -LiteralPath $cachePath) { $known=@((Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json).PSObject.Properties.Name) }
    $script:rows = @(Get-Layout | Where-Object {
        [bool]$_.Identity
    } | Sort-Object Identity)
    $script:updatingModes=$true
    try {
    $grid.Rows.Clear(); $primary.Items.Clear(); $script:modeOptions=@{}
    $number=0
    foreach ($row in $script:rows) {
        $number++
        $m=$row.Mode
        if (-not $m -and $row.Name -in $known) {
            $saved=Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
            $bytes=[Convert]::FromBase64String($saved.PSObject.Properties[$row.Name].Value)
            if ($bytes.Length -ne 220) { throw "Invalid saved mode for $($row.Name)" }
            $ptr=[Runtime.InteropServices.Marshal]::AllocHGlobal(220)
            try {
                [Runtime.InteropServices.Marshal]::Copy($bytes,0,$ptr,220)
                $m=[Runtime.InteropServices.Marshal]::PtrToStructure($ptr,[type][MonitorSwitch+Mode])
            } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr) }
        }
        $options=@([MonitorSwitch]::Modes($row.Name))
        foreach ($setup in $script:saved.Values) {
            if (-not $setup.Identities) { continue }
            foreach ($oldName in $setup.Names) {
                $id=if ($setup.Identities -is [System.Collections.IDictionary]) { $setup.Identities[$oldName] } else { $setup.Identities.PSObject.Properties[$oldName].Value }
                if ($id -ne $row.Identity) { continue }
                $choice=if ($setup.Modes -is [System.Collections.IDictionary]) { $setup.Modes[$oldName] } else { $setup.Modes.PSObject.Properties[$oldName].Value }
                if ($choice -and $choice.Resolution -match '^(\d+) x (\d+)$') {
                    $savedMode=New-Object MonitorSwitch+Mode
                    $savedMode.size=220; $savedMode.bitsPerPixel=32; $savedMode.width=[uint32]$Matches[1]; $savedMode.height=[uint32]$Matches[2]; $savedMode.frequency=[uint32]$choice.Hz
                    if (-not $row.Enabled) { $m=$savedMode }
                    if (-not @($options | Where-Object { $_.width -eq $savedMode.width -and $_.height -eq $savedMode.height -and $_.frequency -eq $savedMode.frequency }).Count) { $options+=$savedMode }
                }
            }
        }
        if ($m) { $options=@($options | Where-Object orientation -eq $m.orientation) }
        if (-not $options.Count -and $m -and $m.width -gt 0) { $options=@($m) }
        $script:modeOptions[$row.Name]=$options
        $index=$grid.Rows.Add([bool]$row.Enabled,"Monitor $number",$row.Name)
        $grid.Rows[$index].Cells['SetPrimary'].Value='Set primary'
        $cell=$grid.Rows[$index].Cells['Resolution']
        foreach ($res in @($options | Sort-Object width,height | ForEach-Object { "$($_.width) x $($_.height)" } | Select-Object -Unique)) { $null=$cell.Items.Add($res) }
        $preferred=if ($m) { "$($m.width) x $($m.height)" } else { '' }
        if ($cell.Items.Count) {
            $cell.Value=if ($cell.Items.Contains($preferred)) { $preferred } else { $cell.Items[$cell.Items.Count-1] }
            Update-Hz $index $(if ($m) { $m.frequency } else { 0 })
        }
        $null=$primary.Items.Add($row.Name)
        if ($row.Primary) { $primary.SelectedItem=$row.Name }
    }
    } finally { $script:updatingModes=$false }
}
function Read-Selection([switch]$AllowIncomplete) {
    $grid.EndEdit() | Out-Null
    $selected=@()
    $modeChoices=@{}
    $identities=@{}
    for ($i=0; $i -lt $script:rows.Count; $i++) {
        if ($grid.Rows[$i].Cells['On'].Value) {
            $name=$script:rows[$i].Name
            $selected += $name
            $identities[$name]=$script:rows[$i].Identity
            $modeChoices[$name]=[pscustomobject]@{ Resolution=[string]$grid.Rows[$i].Cells['Resolution'].Value; Hz=[string]$grid.Rows[$i].Cells['Hz'].Value }
        }
    }
    if (-not $AllowIncomplete) {
        if ($selected.Count -eq 0) { throw 'Select at least one monitor.' }
        if ($primary.SelectedItem -notin $selected) { throw 'Choose a primary monitor that is switched on.' }
    }
    return [pscustomobject]@{ Names=$selected; Primary=[string]$primary.SelectedItem; Modes=$modeChoices; Identities=$identities }
}
function Get-RequestedLayout($selection) {
    $cache=@{}
    $cachePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'data\monitor-modes.json'
    if (Test-Path -LiteralPath $cachePath) {
        $data=Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
        foreach ($p in $data.PSObject.Properties) { $cache[$p.Name]=$p.Value }
    }
    $result=@(); $x=0; $offset=0
    foreach ($name in $selection.Names) {
        $row=$script:rows | Where-Object Name -eq $name | Select-Object -First 1
        if (-not $row) { throw "Monitor is unavailable: $name" }
        $m=$row.Mode
        if (-not $m -and $cache.ContainsKey($name)) {
            $bytes=[Convert]::FromBase64String($cache[$name])
            if ($bytes.Length -ne 220) { throw "Invalid saved mode for $name" }
            $ptr=[Runtime.InteropServices.Marshal]::AllocHGlobal(220)
            try {
                [Runtime.InteropServices.Marshal]::Copy($bytes,0,$ptr,220)
                $m=[Runtime.InteropServices.Marshal]::PtrToStructure($ptr,[type][MonitorSwitch+Mode])
            } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr) }
        }
        if (-not $m) { $m=[MonitorSwitch]::Read($name,-2) }
        if ($selection.Modes) {
            $choice=if ($selection.Modes -is [System.Collections.IDictionary]) { $selection.Modes[$name] } else { $selection.Modes.PSObject.Properties[$name].Value }
            if ($choice) {
                $matches=@($script:modeOptions[$name] | Where-Object { "$($_.width) x $($_.height)" -eq $choice.Resolution -and [string]$_.frequency -eq [string]$choice.Hz })
                if (-not $matches.Count) { throw "Unsupported mode for ${name}: $($choice.Resolution) at $($choice.Hz) Hz. Choose another mode or refresh monitors." }
                $m=$matches | Sort-Object displayFlags | Select-Object -First 1
            }
        }
        if ($m.width -eq 0 -or $m.height -eq 0) { throw "Enable $name in Windows Display Settings once to save its resolution." }
        $m.x=$x; $m.y=0
        if ($name -eq $selection.Primary) { $offset=$x }
        $result += [pscustomobject]@{ Name=$name; Identity=$row.Identity; Enabled=$true; Primary=($name -eq $selection.Primary); Mode=$m }
        $x += [int]$m.width
    }
    foreach ($row in $result) { $row.Mode.x -= $offset }
    return $result
}
function Show-Error($errorRecord) {
    Write-MonitorError 'Settings action' $errorRecord
    [Windows.Forms.MessageBox]::Show($form,$errorRecord.Exception.Message + "`n`nDetails saved in SimSwitch.log",'SimSwitch') | Out-Null
}
$refresh.Add_Click({ try {
    $script:setupDrafts[$script:editingSetup]=Read-Selection -AllowIncomplete
    Refresh-Monitors
    Load-Selection $script:setupDrafts[$script:editingSetup] -Draft
} catch { Show-Error $_ } })
function Load-Selection($selection, [switch]$Draft) {
    if (-not $selection) { throw 'Choose a configured setup.' }
    $selection=Resolve-Setup $selection
    if (-not $Draft) {
    foreach ($name in $selection.Names) { if ($name -notin $script:rows.Name) { throw "Monitor unavailable: $name" } }
    $null=Get-RequestedLayout $selection
    }
    $script:updatingModes=$true
    try {
        for ($i=0; $i -lt $script:rows.Count; $i++) {
            $name=$script:rows[$i].Name
            $grid.Rows[$i].Cells['On'].Value=($name -in $selection.Names)
            $choice=$null
            if ($selection.Modes) { $choice=if ($selection.Modes -is [System.Collections.IDictionary]) { $selection.Modes[$name] } else { $selection.Modes.PSObject.Properties[$name].Value } }
            if ($choice -and $name -in $selection.Names) {
                $grid.Rows[$i].Cells['Resolution'].Value=[string]$choice.Resolution
                Update-Hz $i $choice.Hz
            }
        }
    } finally { $script:updatingModes=$false }
    $primary.SelectedItem=$selection.Primary
    if (-not $Draft) { $status.Text='Setup loaded. Click Apply selection to switch monitors.' }
}
function Select-Setup([string]$name) {
    if ($script:editingSetup) { $script:setupDrafts[$script:editingSetup]=Read-Selection -AllowIncomplete }
    Load-Selection $script:setupDrafts[$name] -Draft
    $script:editingSetup=$name
    $form.Text="SimSwitch - Editing $name setup"
    $status.Text="Editing $name. Choose monitors, primary, resolution and Hz. Save both setups when ready."
}
$setupSelector.Add_SelectedIndexChanged({
    if ($script:selectingSetup -or -not $script:setupDrafts.Count) { return }
    try { Select-Setup ([string]$setupSelector.SelectedItem) } catch { Show-Error $_ }
})
function Save-AllSetups {
    $script:setupDrafts[$script:editingSetup]=Read-Selection -AllowIncomplete
    $all=@{}
    foreach ($name in 'Desktop','Sim rig') {
        $selection=$script:setupDrafts[$name]
        if (-not $selection -or @($selection.Names).Count -eq 0 -or $selection.Primary -notin $selection.Names) { throw "${name}: select at least one monitor and choose a primary among them." }
        try { $null=Get-RequestedLayout $selection } catch { throw "${name}: $($_.Exception.Message)" }
        $all[$name]=$selection
    }
    $null=[IO.Directory]::CreateDirectory((Split-Path $presetPath -Parent))
    $temporary=$presetPath + '.' + $PID + '.tmp'
    $all | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $presetPath -Force
    # Separate the saved configuration from editable drafts.
    $script:saved=@{}
    $copy=$all | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    foreach ($name in 'Desktop','Sim rig') { $script:saved[$name]=$copy.PSObject.Properties[$name].Value }
    Write-MonitorLog 'Both setups saved' $script:saved
    $status.Text='Desktop and Sim rig saved. The switch buttons and tray toggle use these setups.'
}
$saveAll.Add_Click({ try { Save-AllSetups } catch { Show-Error $_ } })
function Switch-ButtonSetup([string]$name) {
    if ($script:worker) { throw 'Keep or revert the pending change first.' }
    if (-not $script:saved.ContainsKey($name)) { throw 'Configure Desktop and Sim rig, then click Save both setups first.' }
    $script:setupDrafts[$script:editingSetup]=Read-Selection -AllowIncomplete
    Refresh-Monitors
    Load-Selection $script:saved[$name]
    $apply.PerformClick()
}
$rigButton.Add_Click({ try { Switch-ButtonSetup 'Sim rig' } catch { Show-Error $_ } })
$deskButton.Add_Click({ try { Switch-ButtonSetup 'Desktop' } catch { Show-Error $_ } })
$apply.Add_Click({ try {
    $selection=Read-Selection
    $requested=@(Get-RequestedLayout $selection)
    $script:transaction=Join-Path ([IO.Path]::GetTempPath()) ('SimSwitch-' + [Guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $script:transaction
    $requested | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $script:transaction 'requested.json')
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=Join-Path $PSHOME 'powershell.exe'
    $info.Arguments='-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'Apply-Monitor-Layout.ps1') + '" -Transaction "' + $script:transaction + '"'
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $script:worker=[Diagnostics.Process]::Start($info)
    foreach ($c in @($grid,$primary,$refresh,$setupSelector,$saveAll,$apply,$rigButton,$deskButton)) { $c.Enabled=$false }
    $status.Text='Applying monitors...'; $script:readyAt=$null
} catch { Show-Error $_ } })
$keep.Add_Click({ 'Keep' | Set-Content -LiteralPath (Join-Path $script:transaction 'keep'); $keep.Enabled=$false })
$revert.Add_Click({ 'Revert' | Set-Content -LiteralPath (Join-Path $script:transaction 'revert'); $keep.Enabled=$false; $revert.Enabled=$false })
$timer=New-Object Windows.Forms.Timer
$timer.Interval=200
$timer.Add_Tick({
    if (-not $script:worker) { return }
    if ($script:worker.HasExited) {
        $errorPath=Join-Path $script:transaction 'error.txt'
        $donePath=Join-Path $script:transaction 'done'
        $status.Text=if (Test-Path -LiteralPath $errorPath) { Get-Content -LiteralPath $errorPath -Raw } elseif (Test-Path -LiteralPath $donePath) { (Get-Content -LiteralPath $donePath -Raw).Trim() + ' monitor layout.' } else { 'Layout worker stopped unexpectedly. Previous layout is in ' + $script:transaction }
        $script:worker.Dispose(); $script:worker=$null
        $keep.Enabled=$false; $revert.Enabled=$false
        foreach ($c in @($grid,$primary,$refresh,$setupSelector,$saveAll,$apply,$rigButton,$deskButton)) { $c.Enabled=$true }
        try { Refresh-Monitors; Load-Selection $script:setupDrafts[$script:editingSetup] -Draft } catch { Write-MonitorError 'Refresh after apply' $_; $status.Text=$_.Exception.Message }
    } elseif (Test-Path -LiteralPath (Join-Path $script:transaction 'ready')) {
        if (-not $script:readyAt) {
            $script:readyAt=[DateTime]::UtcNow; $keep.Enabled=$true; $revert.Enabled=$true
            $screen=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea
            $form.Location=New-Object Drawing.Point(($screen.X+40),($screen.Y+40))
            $form.Activate()
        }
        $remaining=[Math]::Max(0,20-[int]([DateTime]::UtcNow-$script:readyAt).TotalSeconds)
        $status.Text="Keep this layout? Reverting automatically in $remaining seconds."
    }
})
$form.Add_FormClosing({
    if ($script:worker -and -not $script:worker.HasExited) { 'Revert' | Set-Content -LiteralPath (Join-Path $script:transaction 'revert') }
})
try {
    Refresh-Monitors
    $initial=Read-Selection
    foreach ($name in 'Desktop','Sim rig') {
        $seed=if ($script:saved.ContainsKey($name)) { $script:saved[$name] } else { $initial }
        $script:setupDrafts[$name]=$seed | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }
    $setupSelector.SelectedItem='Desktop'
    if ($Check) {
        foreach ($screen in [Windows.Forms.Screen]::AllScreens) {
            $badge=New-IdentifyBadge $screen
            try {
                if (-not $screen.Bounds.Contains($badge.Bounds)) { throw 'Identify badge is outside the monitor bounds.' }
                "Identify badge ready for $($screen.DeviceName)."
            } finally { $badgeFont=$badge.Tag; $badge.Dispose(); $badgeFont.Dispose() }
        }
        $selected=Read-Selection
        $requested=@(Get-RequestedLayout $selected)
        $roundTrip=$selected | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $restored=@(Get-RequestedLayout $roundTrip)
        if (($requested | ConvertTo-Json -Depth 6 -Compress) -ne ($restored | ConvertTo-Json -Depth 6 -Compress)) { throw 'Preset mode round trip failed.' }
        for ($i=0; $i -lt $script:rows.Count; $i++) {
            $cell=$grid.Rows[$i].Cells['Resolution']
            $script:updatingModes=$true
            try {
                foreach ($res in @($cell.Items)) {
                    $cell.Value=$res; Update-Hz $i 0
                    $rates=@($grid.Rows[$i].Cells['Hz'].Items)
                    foreach ($rate in $rates) {
                        if (-not @($script:modeOptions[$script:rows[$i].Name] | Where-Object { "$($_.width) x $($_.height)" -eq $res -and [string]$_.frequency -eq $rate }).Count) { throw 'Resolution / Hz pairing failed.' }
                        $name=$script:rows[$i].Name
                        $testModes=@{}; $testModes[$name]=[pscustomobject]@{Resolution=$res;Hz=$rate}
                        $testSelection=[pscustomobject]@{Names=@($name);Primary=$name;Modes=$testModes}
                        $testLayout=@(Get-RequestedLayout $testSelection)
                        if ("$($testLayout[0].Mode.width) x $($testLayout[0].Mode.height)" -ne $res -or [string]$testLayout[0].Mode.frequency -ne $rate) { throw 'Requested mode was not carried into the layout.' }
                    }
                }
            } finally { $script:updatingModes=$false }
            "$($script:rows[$i].Name): $($cell.Items.Count) resolutions, $($script:modeOptions[$script:rows[$i].Name].Count) supported modes."
        }
        'Resolution / Hz pairing and preset round trip passed.'
        $badModes=@{}; $badModes[$selected.Names[0]]=[pscustomobject]@{Resolution='1 x 1';Hz='9999'}
        $rejected=$false
        try { $null=Get-RequestedLayout ([pscustomobject]@{Names=@($selected.Names[0]);Primary=$selected.Names[0];Modes=$badModes}) } catch { $rejected=$true }
        if (-not $rejected) { throw 'Unsupported mode was accepted.' }
        'Unsupported mode rejected successfully.'
        $snapshot=@(Get-Layout | Where-Object Enabled)
        foreach ($row in $snapshot) { $row.Name='renumbered-' + $row.Name }
        Assert-Layout $snapshot
        'Physical monitor verification survives renamed DISPLAY devices.'
        $originalPresetPath=$presetPath
        $originalSaved=$script:saved
        try {
            $presetPath=Join-Path ([IO.Path]::GetTempPath()) ('SimSwitch-Setups-Test-' + [Guid]::NewGuid().ToString('N') + '.json')
            $script:saved=@{}
            Select-Setup 'Desktop'
            for ($i=0; $i -lt $script:rows.Count; $i++) { $grid.Rows[$i].Cells['On'].Value=($i -eq 0 -or $i -eq $script:rows.Count-1) }
            $primary.SelectedItem=$script:rows[0].Name
            $desktopExpected=Read-Selection
            Select-Setup 'Sim rig'
            for ($i=0; $i -lt $script:rows.Count; $i++) { $grid.Rows[$i].Cells['On'].Value=($i -eq $script:rows.Count-1) }
            $primary.SelectedItem=$script:rows[-1].Name
            Select-Setup 'Desktop'
            $desktopActual=Read-Selection
            if (($desktopActual.Names -join ',') -ne ($desktopExpected.Names -join ',') -or $desktopActual.Primary -ne $desktopExpected.Primary) { throw 'Switching editors lost the Desktop draft.' }
            Save-AllSetups
            $savedSetups=Get-Content -LiteralPath $presetPath -Raw | ConvertFrom-Json
            if (@($savedSetups.PSObject.Properties).Count -ne 2) { throw 'Save must contain only Desktop and Sim rig.' }
            if (@($savedSetups.'Sim rig'.Names).Count -ne 1 -or $savedSetups.'Sim rig'.Primary -ne $script:rows[-1].Name) { throw 'Overall save lost the independent Sim rig setup.' }
            foreach ($name in 'Desktop','Sim rig') { Load-Selection $savedSetups.PSObject.Properties[$name].Value; $null=Get-RequestedLayout (Read-Selection) }
            Load-Selection $savedSetups.Desktop
            $diskBefore=Get-Content -LiteralPath $presetPath -Raw
            foreach ($row in $grid.Rows) { $row.Cells['On'].Value=$false }
            Select-Setup 'Sim rig'; Select-Setup 'Desktop'
            if (@((Read-Selection -AllowIncomplete).Names).Count -ne 0) { throw 'Incomplete draft was lost when switching editors.' }
            $invalidRejected=$false
            try { Save-AllSetups } catch { $invalidRejected=$true }
            if (-not $invalidRejected -or (Get-Content -LiteralPath $presetPath -Raw) -ne $diskBefore) { throw 'Invalid overall save overwrote the saved setups.' }
            'Independent setup editing, overall save/reload, and invalid-save protection passed.'
        } finally { $presetPath=$originalPresetPath; $script:saved=$originalSaved }
        "UI ready: $($grid.Rows.Count) monitors, $($requested.Count) selected; primary $($selected.Primary). No display changes applied."
    } else {
        if ($PresetName) {
            Load-Selection $script:saved[$PresetName]
            if ($ApplyPreset) { $form.Add_Shown({ $apply.PerformClick() }) }
        }
        $timer.Start(); [Windows.Forms.Application]::Run($form)
    }
} finally {
    Close-Identify; $identifyTimer.Dispose()
    $timer.Dispose(); $form.Dispose()
    if (-not $Check) { $settingsMutex.ReleaseMutex() }
    $settingsMutex.Dispose()
}
