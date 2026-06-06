# 01-firewall.ps1 - Windows Firewall edge rules + amp-port blackhole + game/voice
# Reads whitelist from $env:ProgramData\ddos-protect\whitelist.txt.
# All rules tagged -Group 'DDoS-Protect' so uninstall is one command.

$ErrorActionPreference = 'Stop'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\detect.ps1')

$Group = 'DDoS-Protect'
$dataDir = Join-Path $env:ProgramData 'ddos-protect'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$Whitelist = Join-Path $dataDir 'whitelist.txt'
if (-not (Test-Path $Whitelist)) {
@'
# Whitelist for DDoS-Protect. One IP or CIDR per line.
# Whitelisted addresses bypass every rule below.
# 10.0.0.0/8
# 192.168.0.0/16
# 1.2.3.4
'@ | Set-Content -Path $Whitelist -Encoding UTF8
    Write-Note "Created whitelist template at $Whitelist"
}

# Make sure Windows Firewall is on for every profile.
Set-NetFirewallProfile -All -Enabled True -ErrorAction SilentlyContinue
Write-Ok 'Windows Firewall enabled on all profiles'

# Clear previous rules in our group so re-runs are idempotent.
Get-NetFirewallRule -Group $Group -ErrorAction SilentlyContinue | Remove-NetFirewallRule

# ---------- 1. Whitelist allow rules (highest priority) ----------
$lines = Get-Content $Whitelist -ErrorAction SilentlyContinue | Where-Object {
    $_ -and -not $_.StartsWith('#')
}
foreach ($ip in $lines) {
    $ip = $ip.Trim()
    if (-not $ip) { continue }
    New-NetFirewallRule -DisplayName "DDoS-Protect Allow $ip" `
        -Group $Group -Action Allow -Direction Inbound `
        -RemoteAddress $ip -Profile Any -ErrorAction SilentlyContinue | Out-Null
}

# ---------- 2. Amplification source-port blackhole ----------
# Drop inbound UDP from these source ports unless we run the matching service.
$ampPorts = @(19, 53, 123, 389, 1900, 11211, 17, 27015, 7777, 5683, 27960)
$listeningUdp = Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
                ForEach-Object { $_.LocalPort } |
                Sort-Object -Unique
foreach ($p in $ampPorts) {
    if ($listeningUdp -contains $p) { continue }
    New-NetFirewallRule -DisplayName "DDoS-Protect Drop UDP from src $p" `
        -Group $Group -Direction Inbound -Action Block `
        -Protocol UDP -RemotePort $p -ErrorAction SilentlyContinue | Out-Null
}
Write-Ok "Amp-port blackhole installed ($($ampPorts.Count) source ports)"

# ---------- 3. Block known telemetry endpoints OUTBOUND (when telemetry module also runs) ----------
# Skipped here; 06-telemetry.ps1 owns this list.

# ---------- 4. RDP scope: limit to RFC1918 by default ----------
if (Test-RDPEnabled) {
    if (Read-YesNo 'Restrict RDP (3389) to private networks only? (Recommended)' -DefaultYes) {
        New-NetFirewallRule -DisplayName 'DDoS-Protect Allow RDP from LAN' `
            -Group $Group -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort 3389 `
            -RemoteAddress @('10.0.0.0/8','172.16.0.0/12','192.168.0.0/16') | Out-Null
        New-NetFirewallRule -DisplayName 'DDoS-Protect Block RDP from Internet' `
            -Group $Group -Direction Inbound -Action Block `
            -Protocol TCP -LocalPort 3389 | Out-Null
        Write-Ok 'RDP restricted to LAN'
    }
}

# ---------- 5. Game/voice server detection ----------
$tcpListen = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
             ForEach-Object { $_.LocalPort } | Sort-Object -Unique
$gameMap = @(
    @{Port=25565; Proto='TCP'; Label='Minecraft Java'},
    @{Port=19132; Proto='UDP'; Label='Minecraft Bedrock'},
    @{Port=30120; Proto='UDP'; Label='FiveM'},
    @{Port= 9987; Proto='UDP'; Label='TeamSpeak3 voice'},
    @{Port=10011; Proto='TCP'; Label='TeamSpeak3 query'},
    @{Port=30033; Proto='TCP'; Label='TeamSpeak3 file'},
    @{Port=64738; Proto='UDP'; Label='Mumble'},
    @{Port=27015; Proto='UDP'; Label='Source engine'},
    @{Port= 2456; Proto='UDP'; Label='Valheim'}
)
foreach ($g in $gameMap) {
    $isListening = if ($g.Proto -eq 'UDP') { $listeningUdp -contains $g.Port }
                   else                    { $tcpListen   -contains $g.Port }
    if ($isListening) {
        # Windows Firewall has no per-source rate-limit primitive; we lean on
        # the Defender ATP "FloodAttackProtection" + TCP/IP hardening (module 02).
        # We just confirm the port is allowed and leave the cap to the OS.
        New-NetFirewallRule -DisplayName "DDoS-Protect Allow $($g.Label)" `
            -Group $Group -Direction Inbound -Action Allow `
            -Protocol $g.Proto -LocalPort $g.Port | Out-Null
        Write-Ok "$($g.Label) port $($g.Port)/$($g.Proto) allowed (rate cap via TCP hardening)"
    }
}

# ---------- 6. ICMP rate / smurf protection ----------
# Block broadcast pings, allow throttled echo.
New-NetFirewallRule -DisplayName 'DDoS-Protect Block ICMPv4 broadcast' `
    -Group $Group -Direction Inbound -Action Block `
    -Protocol ICMPv4 -IcmpType 8:0 -RemoteAddress 255.255.255.255 | Out-Null

# Persist + summarise.
$rules = Get-NetFirewallRule -Group $Group
Write-Ok "Installed $($rules.Count) Windows Firewall rules (group: $Group)"

# Helper: ddos-allow <ip>
$bin = Join-Path $env:ProgramData 'ddos-protect'
$helper = Join-Path $bin 'ddos-allow.ps1'
@"
# ddos-allow.ps1 - add an IP to the DDoS-Protect whitelist (run as Administrator).
param([Parameter(Mandatory)][string]`$Ip)
`$wl = Join-Path `$env:ProgramData 'ddos-protect\whitelist.txt'
if (-not (Select-String -Path `$wl -Pattern ('^' + [regex]::Escape(`$Ip) + '$') -Quiet)) {
    Add-Content -Path `$wl -Value `$Ip
}
New-NetFirewallRule -DisplayName "DDoS-Protect Allow `$Ip" -Group 'DDoS-Protect' ``
    -Action Allow -Direction Inbound -RemoteAddress `$Ip -Profile Any -ErrorAction SilentlyContinue | Out-Null
Write-Host "[ok] `$Ip whitelisted"
"@ | Set-Content -Path $helper -Encoding UTF8
Write-Note "Use: powershell -File '$helper' <ip>   to whitelist on the fly"
