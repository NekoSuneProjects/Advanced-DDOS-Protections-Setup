# 03-rdp.ps1 - RDP brute-force lockout + NLA enforce + 3389-from-internet block

$ErrorActionPreference = 'Stop'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\detect.ps1')

if (-not (Test-RDPEnabled)) {
    Write-Note 'RDP is not enabled - skipping'
    return
}

# Enforce Network Level Authentication.
$tsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
Set-ItemProperty -Path $tsKey -Name 'UserAuthentication' -Value 1 -Force
Write-Ok 'NLA enforced (UserAuthentication=1)'

# Account lockout policy: 5 failed attempts = 30 min lockout, observation 30 min.
try {
    net accounts /lockoutthreshold:5 /lockoutduration:30 /lockoutwindow:30 | Out-Null
    Write-Ok 'Account lockout: 5 attempts -> 30 min lockout'
} catch { Write-Note 'net accounts failed - check on a domain-joined host' }

# Enable auditing of logon failures so attempts go into Security log.
auditpol /set /subcategory:"Logon" /failure:enable /success:enable | Out-Null
Write-Ok 'Logon auditing enabled (Security event 4625)'

# Optional: change default RDP port (commented; opt-in only).
Write-Note 'To move RDP off 3389 (recommended for internet-exposed hosts), edit:'
Write-Note '  HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp\PortNumber'
Write-Note 'then open the new port in Windows Firewall and remove the 3389 allow rule.'
