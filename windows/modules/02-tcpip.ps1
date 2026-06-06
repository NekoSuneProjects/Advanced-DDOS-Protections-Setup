# 02-tcpip.ps1 - TCP/IP stack hardening. Saves each previous value to state.json
# under tcpip.<name> so uninstall.ps1 can put it back exactly.

$ErrorActionPreference = 'Stop'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')

$StateFile = $env:DDOS_STATE_FILE
$state = Get-Content -Raw $StateFile | ConvertFrom-Json

$tcpipKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'

$hardenings = @{
    'SynAttackProtect'              = 1
    'TcpMaxHalfOpen'                = 100
    'TcpMaxHalfOpenRetried'         = 80
    'EnableICMPRedirect'            = 0
    'DisableIPSourceRouting'        = 2
    'EnableDeadGWDetect'            = 0
    'KeepAliveTime'                 = 300000
    'TcpMaxConnectRetransmissions'  = 2
    'TcpMaxDataRetransmissions'     = 3
    'PerformRouterDiscovery'        = 0
    'EnablePMTUDiscovery'           = 1
    'EnablePMTUBHDetect'            = 0
    'IPEnableRouter'                = 0
    'AllowUnqualifiedQuery'         = 0
    'TcpTimedWaitDelay'             = 30
}

if (-not $state.tcpip) { $state | Add-Member -NotePropertyName tcpip -NotePropertyValue (New-Object PSObject) -Force }
foreach ($name in $hardenings.Keys) {
    $existing = (Get-ItemProperty -Path $tcpipKey -Name $name -ErrorAction SilentlyContinue).$name
    if ($null -eq $existing) {
        Add-Member -InputObject $state.tcpip -NotePropertyName $name -NotePropertyValue '__delete__' -Force
    } else {
        Add-Member -InputObject $state.tcpip -NotePropertyName $name -NotePropertyValue $existing -Force
    }
    New-ItemProperty -Path $tcpipKey -Name $name -PropertyType DWord `
        -Value $hardenings[$name] -Force | Out-Null
    Write-Note "$name -> $($hardenings[$name])"
}

# Disable SMBv1 (CVE-soup, no DDoS-direct but well-known backdoor surface).
try {
    $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
    if ($smb1 -and $smb1.State -eq 'Enabled') {
        Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null
        Write-Ok 'SMBv1 disabled'
    }
} catch { }

# Persist state.
$state | ConvertTo-Json -Depth 6 | Set-Content -Path $StateFile -Encoding UTF8

Write-Ok 'TCP/IP hardening applied. Reboot to take full effect.'
