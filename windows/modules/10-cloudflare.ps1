# 10-cloudflare.ps1 - Cloudflare integration (under-attack mode toggle + ban list)
# Writes %ProgramData%\ddos-protect\cloudflare.json (ACL: SYSTEM + Administrators only)
# and installs a ddos-cf.ps1 helper.

$ErrorActionPreference = 'Stop'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')

$dataDir = Join-Path $env:ProgramData 'ddos-protect'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$confPath = Join-Path $dataDir 'cloudflare.json'

# Re-use existing if present.
$existing = $null
if (Test-Path $confPath) { $existing = Get-Content -Raw $confPath | ConvertFrom-Json }

Write-Note 'Cloudflare config:'
Write-Note '  Token: https://dash.cloudflare.com/profile/api-tokens'
Write-Note '  Permissions needed: Zone:Zone:Edit, Zone:Firewall Services:Edit'
$tok = Read-Host '  Cloudflare API token (Bearer)'
$zid = Read-Host '  Cloudflare Zone ID'
if (-not $tok -and $existing) { $tok = $existing.ApiToken }
if (-not $zid -and $existing) { $zid = $existing.ZoneId }

@{ ApiToken = $tok; ZoneId = $zid } | ConvertTo-Json | Set-Content $confPath -Encoding UTF8

# Restrict file ACL to Administrators + SYSTEM.
$acl = Get-Acl $confPath
$acl.SetAccessRuleProtection($true, $false)
foreach ($id in @('SYSTEM','Administrators')) {
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $id, 'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl $confPath $acl
Write-Ok "Saved $confPath (ACL: SYSTEM + Administrators only)"

# Install helper script.
$helper = Join-Path $dataDir 'ddos-cf.ps1'
@'
# ddos-cf.ps1 - tiny Cloudflare ops helper. Use:
#   .\ddos-cf.ps1 on
#   .\ddos-cf.ps1 off
#   .\ddos-cf.ps1 block 1.2.3.4
#   .\ddos-cf.ps1 unblock 1.2.3.4
#   .\ddos-cf.ps1 list
param([Parameter(Mandatory)][string]$Action, [string]$Ip)
$conf = Join-Path $env:ProgramData 'ddos-protect\cloudflare.json'
if (-not (Test-Path $conf)) { Write-Error "missing $conf - re-run installer module 10"; return }
$cfg = Get-Content -Raw $conf | ConvertFrom-Json
$headers = @{ Authorization = "Bearer $($cfg.ApiToken)"; 'Content-Type' = 'application/json' }
$base = "https://api.cloudflare.com/client/v4/zones/$($cfg.ZoneId)"
switch ($Action) {
    'on' {
        Invoke-RestMethod -Method Patch -Headers $headers -Uri "$base/settings/security_level" `
            -Body '{"value":"under_attack"}'
    }
    'off' {
        Invoke-RestMethod -Method Patch -Headers $headers -Uri "$base/settings/security_level" `
            -Body '{"value":"medium"}'
    }
    'block' {
        if (-not $Ip) { throw 'IP required' }
        $body = @{ mode='block'; configuration=@{target='ip';value=$Ip}; notes="ddos-protect: $Ip" } | ConvertTo-Json
        Invoke-RestMethod -Method Post -Headers $headers -Uri "$base/firewall/access_rules/rules" -Body $body
    }
    'unblock' {
        if (-not $Ip) { throw 'IP required' }
        $r = Invoke-RestMethod -Headers $headers -Uri "$base/firewall/access_rules/rules?configuration_value=$Ip"
        $id = $r.result[0].id
        if (-not $id) { Write-Host "no rule for $Ip"; return }
        Invoke-RestMethod -Method Delete -Headers $headers -Uri "$base/firewall/access_rules/rules/$id"
    }
    'list' {
        $r = Invoke-RestMethod -Headers $headers -Uri "$base/firewall/access_rules/rules?per_page=200"
        $r.result | Select-Object @{n='value';e={$_.configuration.value}}, mode, notes
    }
    default { Write-Host "Usage: ddos-cf.ps1 {on|off|block <ip>|unblock <ip>|list}" }
}
'@ | Set-Content -Path $helper -Encoding UTF8

Write-Ok "Helper installed: $helper"
Write-Note '  .\ddos-cf.ps1 on        # enable Under Attack mode'
Write-Note '  .\ddos-cf.ps1 list      # show access rules'
