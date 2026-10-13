param([switch]$Check)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Monitor-Logging.ps1')
trap {
    Write-MonitorError 'Tray unhandled error' $_
    $details = ($_ | Out-String) + [Environment]::NewLine + $_.ScriptStackTrace
    $details | Set-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'logs\Monitor-Tray-error.log')
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show($_.Exception.Message + "`n`nDetails saved in Monitor-Tray-error.log", 'Monitor tray startup failed') | Out-Null
    } catch {}
    exit 1
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
public static class TrayArt {
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
    public static Icon Make(bool wheel) {
        using (var bitmap = new Bitmap(32,32))
        using (var g = Graphics.FromImage(bitmap))
        using (var pen = new Pen(Color.White, 2.6f))
        using (var fill = new SolidBrush(wheel ? Color.FromArgb(232,133,37) : Color.FromArgb(65,104,230))) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            g.FillEllipse(fill, 0,0,32,32);
            if (wheel) {
                g.DrawEllipse(pen,5,5,22,22);
                g.DrawEllipse(pen,13,13,6,6);
                g.DrawLine(pen,6,12,13,15);
                g.DrawLine(pen,26,12,19,15);
                g.DrawLine(pen,16,19,16,27);
            } else {
                PointF[] outline = { new PointF(9,9), new PointF(23,9), new PointF(28,23), new PointF(23,25), new PointF(19,20), new PointF(13,20), new PointF(9,25), new PointF(4,23) };
                g.DrawPolygon(pen,outline);
                g.DrawLine(pen,8,15,14,15);
                g.DrawLine(pen,11,12,11,18);
                g.FillEllipse(Brushes.White,21,12,3,3);
                g.FillEllipse(Brushes.White,24,16,3,3);
            }
            IntPtr handle = bitmap.GetHicon();
            try { using (var icon = Icon.FromHandle(handle)) { return (Icon)icon.Clone(); } }
            finally { DestroyIcon(handle); }
        }
    }
}
'@ -ReferencedAssemblies System.Drawing

$scriptPath = Join-Path $PSScriptRoot 'Toggle-Monitors.ps1'
function New-SwitchProcess([string]$mode) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $PSHOME 'powershell.exe'
    $info.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '" -Mode ' + $mode
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    return [Diagnostics.Process]::Start($info)
}
$controller = [TrayArt]::Make($false)
$wheel = [TrayArt]::Make($true)
if ($Check) {
    $p = New-SwitchProcess 'Status'
    $p.WaitForExit()
    Write-Output ('Current setup: ' + $p.StandardOutput.ReadToEnd().Trim())
    $code = $p.ExitCode
    $p.Dispose(); $controller.Dispose(); $wheel.Dispose()
    if ($code -ne 0) { throw 'Status check failed.' }
    'Both tray icons rendered successfully.'
    exit 0
}
$mutex = New-Object Threading.Mutex($false, 'Local\SimSwitchMonitorTray')
if (-not $mutex.WaitOne(0)) {
    $mutex.Dispose(); $controller.Dispose(); $wheel.Dispose()
    [Windows.Forms.MessageBox]::Show("The monitor tray app is already running.`n`nClick the arrow beside the Windows clock and look for the blue controller or orange steering wheel.`n`nLeft-click that icon to switch monitors. You can drag it beside the clock to keep it visible.", 'Monitor toggle is already running') | Out-Null
    exit
}
[Windows.Forms.Application]::EnableVisualStyles()
$tray = New-Object Windows.Forms.NotifyIcon
$tray.Icon = $wheel
$tray.Text = 'Monitor toggle - checking setup'
$menu = New-Object Windows.Forms.ContextMenuStrip
$settings = $menu.Items.Add('Choose monitors / saved presets...')
$settings.Add_Click({
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $PSHOME 'powershell.exe'
    $info.Arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'Monitor-Settings.ps1') + '"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $null = [Diagnostics.Process]::Start($info)
})
$null = $menu.Items.Add('-')
$gaming = $menu.Items.Add('Desktop setup')
$sim = $menu.Items.Add('Sim rig setup')
$null = $menu.Items.Add('-')
$quit = $menu.Items.Add('Exit')
$tray.ContextMenuStrip = $menu
$script:pending = $null
$script:pendingMode = $null
$script:nextStatus = [DateTime]::MinValue
$context = New-Object Windows.Forms.ApplicationContext
function Start-Action([string]$mode) {
    if ($script:pending) { return }
    try {
        $script:pending = New-SwitchProcess $mode
        $script:pendingMode = $mode
        if ($mode -ne 'Status') { $tray.Text = 'Switching monitors...' }
    } catch { Write-MonitorError 'Tray action' $_; $tray.ShowBalloonTip(5000, 'Monitor toggle', $_.Exception.Message, [Windows.Forms.ToolTipIcon]::Error) }
}
$tray.Add_MouseClick({ param($sender,$e)
    if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) { Start-Action 'Toggle' }
})
$gaming.Add_Click({ Start-Action 'Gaming' })
$sim.Add_Click({ Start-Action 'Sim' })
$quit.Add_Click({ $context.ExitThread() })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    if ($script:pending -and $script:pending.HasExited) {
        $p = $script:pending
        $output = $p.StandardOutput.ReadToEnd().Trim()
        $errorText = $p.StandardError.ReadToEnd().Trim()
        $failed = $p.ExitCode -ne 0
        $p.Dispose(); $script:pending = $null
        if ($failed) {
            Write-MonitorLog 'Tray child failed' @{Mode=$script:pendingMode;Output=$output;Error=$errorText}
            $tray.ShowBalloonTip(5000, 'Monitor toggle failed', ($output + ' ' + $errorText).Trim(), [Windows.Forms.ToolTipIcon]::Error)
        } elseif ($script:pendingMode -eq 'Status') {
            $tray.Icon = if ($output -eq 'Sim') { $controller } else { $wheel }
            $tray.Text = switch ($output) {
                'Gaming' { 'Desktop active. Click to switch to Sim rig.' }
                'Sim' { 'Sim rig active. Click to switch to Desktop.' }
                default { 'Custom layout. Click to switch to Desktop.' }
            }
            $gaming.Checked = $output -eq 'Gaming'
            $sim.Checked = $output -eq 'Sim'
        }
        $script:nextStatus = if ($script:pendingMode -eq 'Status') { [DateTime]::Now.AddSeconds(3) } else { [DateTime]::MinValue }
    }
    if (-not $script:pending -and [DateTime]::Now -ge $script:nextStatus) { Start-Action 'Status' }
})
try {
    $tray.Visible = $true
    $tray.ShowBalloonTip(6000, 'Monitor toggle is ready', 'Look for the controller or steering wheel beside the clock or under its arrow. Left-click the icon to toggle screens.', [Windows.Forms.ToolTipIcon]::Info)
    $timer.Start()
    [Windows.Forms.Application]::Run($context)
} finally {
    $timer.Stop(); $timer.Dispose()
    $tray.Visible = $false; $tray.Dispose(); $menu.Dispose()
    $controller.Dispose(); $wheel.Dispose(); $context.Dispose()
    if ($script:pending) { $script:pending.Dispose() }
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
