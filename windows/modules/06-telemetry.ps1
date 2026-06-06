# 06-telemetry.ps1 - Disable Microsoft telemetry services + block telemetry
# endpoints outbound via Windows Firewall. No hosts-file edits.

$ErrorActionPreference = 'Continue'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')

$StateFile = $env:DDOS_STATE_FILE
$svcFile   = Join-Path $env:DDOS_SCRIPT_DIR 'windows\configs\telemetry-services.txt'
$epFile    = Join-Path $env:DDOS_SCRIPT_DIR 'windows\configs\telemetry-endpoints.txt'
$state = Get-Content -Raw $StateFile | ConvertFrom-Json
if (-not $state.services) { $state | Add-Member -NotePropertyName services -NotePropertyValue (New-Object PSObject) -Force }

# 1) Services.
$services = Get-Content $svcFile | Where-Object { $_ -and -not $_.StartsWith('#') }
foreach ($s in $services) {
    $s = $s.Trim()
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if (-not $svc) { continue }
    $prev = (Get-WmiObject Win32_Service -Filter "Name='$s'" -ErrorAction SilentlyContinue).StartMode
    if (-not $prev) { $prev = 'Manual' }
    Add-Member -InputObject $state.services -NotePropertyName $s -NotePropertyValue $prev -Force
    try {
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
        Set-Service -Name $s -StartupType Disabled
        Write-Ok "$s disabled (was: $prev)"
    } catch { Write-Note "could not disable $s ($_)" }
}

# 2) Registry telemetry knobs.
$telKeys = @(
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection';        Name='AllowTelemetry';       Value=0 },
    @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name='AllowTelemetry'; Value=0 },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat';             Name='DisableInventory';     Value=1 },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo';       Name='DisabledByGroupPolicy';Value=1 },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';          Name='DisableWindowsConsumerFeatures'; Value=1 },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';                Name='EnableActivityFeed';   Value=0 },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';                Name='PublishUserActivities';Value=0 },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';                Name='UploadUserActivities'; Value=0 }
)
foreach ($k in $telKeys) {
    if (-not (Test-Path $k.Path)) { New-Item -Path $k.Path -Force | Out-Null }
    Set-ItemProperty -Path $k.Path -Name $k.Name -Value $k.Value -Type DWord -Force
}
Write-Ok 'Telemetry policy keys applied'

# 3) Outbound firewall blocks for telemetry endpoints.
$endpoints = Get-Content $epFile | Where-Object { $_ -and -not $_.StartsWith('#') }
$blocked = 0
foreach ($host_ in $endpoints) {
    $host_ = $host_.Trim()
    try {
        $ips = [System.Net.Dns]::GetHostAddresses($host_) | ForEach-Object { $_.IPAddressToString }
    } catch { continue }
    foreach ($ip in $ips) {
        New-NetFirewallRule -DisplayName "DDoS-Protect Block telemetry $host_ ($ip)" `
            -Group 'DDoS-Protect' -Direction Outbound -Action Block `
            -RemoteAddress $ip -Profile Any -ErrorAction SilentlyContinue | Out-Null
        $blocked++
    }
}
Write-Ok "Blocked $blocked telemetry destination IPs (firewall, not hosts)"

$state | ConvertTo-Json -Depth 6 | Set-Content -Path $StateFile -Encoding UTF8
