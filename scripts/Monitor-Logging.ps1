if (-not $script:MonitorLogPath) { $script:MonitorLogPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'logs\SimSwitch.log' }
function Write-MonitorLog([string]$Event, $Details) {
    # Logging must never interrupt display restoration.
    try {
        $null = [IO.Directory]::CreateDirectory((Split-Path $script:MonitorLogPath -Parent))
        $entry=[ordered]@{ Time=[DateTimeOffset]::Now.ToString('o'); Process=$PID; Event=$Event; Details=$Details }
        $line=$entry | ConvertTo-Json -Depth 8 -Compress
        Add-Content -LiteralPath $script:MonitorLogPath -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch { [Diagnostics.Debug]::WriteLine('SimSwitch log write failed: ' + $_.Exception.Message) }
}
function Write-MonitorError([string]$Stage, $Record) {
    Write-MonitorLog 'Error' ([ordered]@{
        Stage=$Stage; Message=$Record.Exception.Message; Exception=$Record.Exception.ToString()
        Stack=$Record.ScriptStackTrace; Position=$Record.InvocationInfo.PositionMessage
        ErrorId=$Record.FullyQualifiedErrorId
    })
}
