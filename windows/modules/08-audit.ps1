# 08-audit.ps1 - Read-only audit: autorun entries, services with sketchy paths,
# scheduled tasks created by non-Microsoft accounts, listening ports.
# Writes a report + sends a notification if red flags found.

$ErrorActionPreference = 'Continue'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\notify.ps1')

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = Join-Path $env:ProgramData 'ddos-protect\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$report = Join-Path $logDir "audit-$ts.txt"
$findings = @()

# ----- Listening ports -----
$lines = "===== Listening TCP / UDP ====="
$lines += Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
          Select-Object LocalAddress, LocalPort, OwningProcess,
                        @{n='Process';e={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name}} |
          Format-Table -AutoSize | Out-String
$lines += Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
          Select-Object LocalAddress, LocalPort, OwningProcess,
                        @{n='Process';e={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name}} |
          Format-Table -AutoSize | Out-String

# ----- Services with binPath outside trusted dirs -----
$lines += "===== Suspicious services (binary outside System32 / Program Files) ====="
$trustedRoots = @("$env:SystemRoot\System32","$env:SystemRoot\Syswow64","$env:ProgramFiles","${env:ProgramFiles(x86)}","$env:SystemRoot\WinSxS")
$svcSuspect = Get-WmiObject Win32_Service -ErrorAction SilentlyContinue |
              Where-Object { $_.PathName -and $_.PathName -notmatch '^"?[A-Z]:\\(Windows|Program Files)' } |
              Select-Object Name, StartMode, State, StartName, PathName
$lines += $svcSuspect | Format-Table -AutoSize | Out-String
if ($svcSuspect) { $findings += "$($svcSuspect.Count) suspicious service(s)" }

# ----- Scheduled tasks created outside \Microsoft -----
$lines += "===== Non-Microsoft scheduled tasks ====="
$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
         Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.TaskPath -ne '\' } |
         Select-Object TaskPath, TaskName, State, Author
$lines += $tasks | Format-Table -AutoSize | Out-String

# ----- Autorun: HKLM + HKCU Run keys -----
$lines += "===== Autorun (HKLM/HKCU Run) ====="
$runKeys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
)
foreach ($k in $runKeys) {
    if (-not (Test-Path $k)) { continue }
    $lines += "--- $k ---"
    $lines += Get-ItemProperty -Path $k | Out-String
}

# ----- Failed logons (last hour) -----
$lines += "===== Failed logons last 1h ====="
try {
    $events = Get-WinEvent -FilterHashtable @{LogName='Security'; ID=4625; StartTime=(Get-Date).AddHours(-1)} -ErrorAction SilentlyContinue
    $lines += $events |
              ForEach-Object { "{0}  user={1}  ip={2}" -f $_.TimeCreated, $_.Properties[5].Value, $_.Properties[19].Value } |
              Out-String
    if ($events.Count -gt 50) { $findings += "$($events.Count) failed logons in last hour" }
} catch { }

# ----- Persistence WMI subs (commonly used by malware) -----
$lines += "===== WMI event subscribers ====="
$lines += Get-WmiObject -Namespace root\subscription -Class __EventFilter -ErrorAction SilentlyContinue |
          Select-Object Name, Query | Format-Table -AutoSize | Out-String

# ----- Write + notify -----
$header = "Audit report on $env:COMPUTERNAME @ $(Get-Date)"
($header + "`n" + ($lines -join "`n")) | Set-Content -Path $report -Encoding UTF8
Write-Ok "Audit saved to $report"

if ($findings.Count -gt 0) {
    Send-DDoSNotification -Title "Audit findings on $env:COMPUTERNAME" `
        -Message ("Flags:`n" + ($findings -join "`n") + "`nReport: $report") -Severity warn
}
