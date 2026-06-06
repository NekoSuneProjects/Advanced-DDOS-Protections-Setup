# 12-monitor.ps1 - Realtime watchdog: CPU, RAM, network, TCP conn count.
# Implemented as a Scheduled Task that fires every minute and pushes alerts
# through the configured notification channels.

$ErrorActionPreference = 'Stop'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')

$dataDir = Join-Path $env:ProgramData 'ddos-protect'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

# Thresholds file - edit to tune.
$envPath = Join-Path $dataDir 'monitor.json'
if (-not (Test-Path $envPath)) {
    @{
        CpuPctThreshold        = 85
        MemPctThreshold        = 90
        RxMbpsThreshold        = 400
        TxMbpsThreshold        = 400
        ConnCountThreshold     = 3000
        AlertCooldownSeconds   = 600
    } | ConvertTo-Json | Set-Content -Path $envPath -Encoding UTF8
}

# Watcher script.
$watcher = Join-Path $dataDir 'ddos-watcher.ps1'
@"
# ddos-watcher.ps1 - one shot sample. Scheduled task runs this every 60s.
`$ErrorActionPreference = 'SilentlyContinue'
. '$($env:DDOS_SCRIPT_DIR)\lib\notify.ps1'
`$conf = Get-Content -Raw '$envPath' | ConvertFrom-Json
`$state = '$dataDir\state'
New-Item -ItemType Directory -Force -Path `$state | Out-Null

# CPU%
`$cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average

# Mem%
`$os = Get-CimInstance Win32_OperatingSystem
`$mem = [int]((`$os.TotalVisibleMemorySize - `$os.FreePhysicalMemory) * 100 / `$os.TotalVisibleMemorySize)

# Bandwidth: sample twice and diff.
`$adapter = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' -and `$_.Virtual -eq `$false } | Select-Object -First 1
`$rxMbps = 0; `$txMbps = 0
if (`$adapter) {
    `$s1 = Get-NetAdapterStatistics -Name `$adapter.Name
    Start-Sleep -Seconds 1
    `$s2 = Get-NetAdapterStatistics -Name `$adapter.Name
    `$rxMbps = [int]((`$s2.ReceivedBytes - `$s1.ReceivedBytes) * 8 / 1MB)
    `$txMbps = [int]((`$s2.SentBytes     - `$s1.SentBytes)     * 8 / 1MB)
}

# TCP connection count.
`$conn = (Get-NetTCPConnection -State Established, SynSent, SynReceived -ErrorAction SilentlyContinue).Count

@{ ts=(Get-Date).ToUniversalTime().ToString('o'); cpu=`$cpu; mem=`$mem; rx=`$rxMbps; tx=`$txMbps; conn=`$conn } |
    ConvertTo-Json | Set-Content "`$state\last-sample.json" -Encoding UTF8

function Trip(`$key, `$sev, `$title, `$msg) {
    `$mark = "`$state\cooldown-`$key"
    if (Test-Path `$mark) {
        `$last = [DateTime](Get-Content `$mark)
        if (((Get-Date) - `$last).TotalSeconds -lt `$conf.AlertCooldownSeconds) { return }
    }
    (Get-Date).ToString('o') | Set-Content `$mark
    Send-DDoSNotification -Title `$title -Message `$msg -Severity `$sev
}

if (`$cpu    -ge `$conf.CpuPctThreshold)    { Trip cpu  warn     'High CPU on $env:COMPUTERNAME'         "CPU at `${cpu}% (threshold `$(`$conf.CpuPctThreshold)%)" }
if (`$mem    -ge `$conf.MemPctThreshold)    { Trip mem  warn     'High memory on $env:COMPUTERNAME'      "Mem at `${mem}% (threshold `$(`$conf.MemPctThreshold)%)" }
if (`$rxMbps -ge `$conf.RxMbpsThreshold)    { Trip rx   critical 'Inbound flood on $env:COMPUTERNAME'    "RX `${rxMbps} Mbps on `$(`$adapter.Name)" }
if (`$txMbps -ge `$conf.TxMbpsThreshold)    { Trip tx   warn     'High outbound on $env:COMPUTERNAME'    "TX `${txMbps} Mbps" }
if (`$conn   -ge `$conf.ConnCountThreshold) { Trip conn critical 'TCP conn flood on $env:COMPUTERNAME'   "`${conn} established/syn connections" }
"@ | Set-Content -Path $watcher -Encoding UTF8

# ddos-status helper.
$status = Join-Path $dataDir 'ddos-status.ps1'
@"
`$f = '$dataDir\state\last-sample.json'
if (-not (Test-Path `$f)) { Write-Host 'no sample yet'; return }
`$s = Get-Content -Raw `$f | ConvertFrom-Json
'Host:    {0}' -f `$env:COMPUTERNAME
'Sample:  {0}' -f `$s.ts
'CPU:     {0}%' -f `$s.cpu
'Mem:     {0}%' -f `$s.mem
'RX:      {0} Mbps' -f `$s.rx
'TX:      {0} Mbps' -f `$s.tx
'TCP:     {0}' -f `$s.conn
"@ | Set-Content -Path $status -Encoding UTF8

# Scheduled task @ every minute.
$tName = 'DDoS-Protect Watcher'
Unregister-ScheduledTask -TaskName $tName -Confirm:$false -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$watcher`""
$trigger = New-ScheduledTaskTrigger -Once -At ([DateTime]::Now.AddMinutes(1)) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration ([TimeSpan]::FromDays(365000))
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName $tName -Action $action -Trigger $trigger `
    -Principal $principal -Description 'CPU/Mem/Network/TCP watchdog' | Out-Null

Write-Ok "Watcher task installed: $tName (every 60s)"
Write-Note "Tune thresholds:  $envPath"
Write-Note "Last sample:      powershell -File `"$status`""
