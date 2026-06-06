# ddos-protect.ps1 - master on/off/status switch for Windows.
# Installed to %ProgramData%\ddos-protect\ddos-protect.ps1 by install.ps1.
#
# Usage (elevated PowerShell):
#   ddos-protect on        # enable firewall rules + watcher + 4625 task
#   ddos-protect off       # disable everything but keep configs
#   ddos-protect status    # show component state
#   ddos-protect restart   # off then on
#
# Persistence: runtime toggle only. Reboot restores the install state.
# For permanent removal use uninstall.ps1.
param([Parameter(Position=0)][string]$Command = 'status')

$ErrorActionPreference = 'Stop'

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Run this in an elevated PowerShell (Run as administrator).' -ForegroundColor Red
        exit 1
    }
}

function Set-FwState   { param([bool]$Enabled)
    $rules = Get-NetFirewallRule -Group 'DDoS-Protect' -ErrorAction SilentlyContinue
    if ($rules) { $rules | Set-NetFirewallRule -Enabled ([bool]$Enabled) }
}
function Get-FwState   {
    $rules = Get-NetFirewallRule -Group 'DDoS-Protect' -ErrorAction SilentlyContinue
    if (-not $rules) { return 'absent' }
    $on = ($rules | Where-Object Enabled -eq 'True').Count
    if ($on -ge ($rules.Count / 2)) { 'on' } else { 'off' }
}

function Set-TaskState { param([string]$Name, [bool]$Enabled)
    $t = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if (-not $t) { return }
    if ($Enabled) { Enable-ScheduledTask -TaskName $Name | Out-Null }
    else          { Disable-ScheduledTask -TaskName $Name | Out-Null }
}
function Get-TaskState {
    param([string]$Name)
    $t = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if (-not $t)           { return 'absent' }
    if ($t.State -eq 'Disabled') { 'off' } else { 'on' }
}

function Paint { param([string]$s)
    switch ($s) {
        'on'     { Write-Host 'on'     -ForegroundColor Green -NoNewline }
        'off'    { Write-Host 'off'    -ForegroundColor Red   -NoNewline }
        'absent' { Write-Host 'absent' -ForegroundColor DarkGray -NoNewline }
        default  { Write-Host $s       -ForegroundColor Yellow -NoNewline }
    }
}

function Show-Status {
    Write-Host 'ddos-protect status:' -ForegroundColor DarkGray
    Write-Host '  Firewall:   ' -NoNewline; Paint (Get-FwState); Write-Host ''
    Write-Host '  Watcher:    ' -NoNewline; Paint (Get-TaskState 'DDoS-Protect Watcher'); Write-Host ''
    Write-Host '  4625 alert: ' -NoNewline; Paint (Get-TaskState 'DDoS-Protect Audit Burst'); Write-Host ''
}

$Script:RepoRaw = 'https://raw.githubusercontent.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup/main'

function Get-CurrentVersion {
    $f = Join-Path $env:ProgramData 'ddos-protect\version'
    if (Test-Path $f) { (Get-Content -TotalCount 1 -Path $f).Trim() } else { '1.0.0' }
}
function Get-InstallDir {
    $f = Join-Path $env:ProgramData 'ddos-protect\version'
    if (Test-Path $f) {
        $lines = Get-Content -Path $f
        if ($lines.Count -ge 2) { return $lines[1].Trim() }
    }
    return (Join-Path $env:ProgramData 'ddos-protect-src')
}

function Show-Version {
    Write-Host ('ddos-protect ') -NoNewline
    Write-Host ("v$(Get-CurrentVersion)") -ForegroundColor Green -NoNewline
    Write-Host ("   (install dir: $(Get-InstallDir))") -ForegroundColor DarkGray
}

function Test-Update {
    param([string]$Current = (Get-CurrentVersion))
    try {
        $cl = Invoke-WebRequest -Uri "$($Script:RepoRaw)/CHANGELOG.md" -TimeoutSec 10 -UseBasicParsing
        $body = $cl.Content
    } catch {
        Write-Host 'Could not fetch CHANGELOG.md from GitHub' -ForegroundColor Red
        return $null
    }
    $m = [regex]::Match($body, '(?m)^## \[(\d+\.\d+\.\d+)\]')
    if (-not $m.Success) {
        Write-Host 'Could not parse latest version from CHANGELOG.md' -ForegroundColor Red
        return $null
    }
    $latest = $m.Groups[1].Value

    if ($Current -eq $latest) {
        Write-Host "Up to date " -ForegroundColor Green -NoNewline
        Write-Host "(v$Current)"
        return @{ Latest=$latest; HasUpdate=$false; Changelog='' }
    }
    if ([version]$latest -lt [version]$Current) {
        Write-Host "Local v$Current is ahead of GitHub v$latest" -ForegroundColor Yellow
        return @{ Latest=$latest; HasUpdate=$false; Changelog='' }
    }

    Write-Host "Update available: " -ForegroundColor Yellow -NoNewline
    Write-Host "v$Current -> v$latest" -ForegroundColor Green
    Write-Host ''

    # Slice the changelog from latest's heading down to current's heading.
    $start = $body.IndexOf("## [$latest]")
    $end   = $body.IndexOf("## [$Current]")
    if ($end -lt 0) { $end = $body.Length }
    Write-Host ('-- Changelog ' + ('-' * 40)) -ForegroundColor DarkGray
    Write-Host ($body.Substring($start, $end - $start).TrimEnd())
    Write-Host ('-' * 53) -ForegroundColor DarkGray
    return @{ Latest=$latest; HasUpdate=$true; Changelog=$body.Substring($start, $end - $start) }
}

function Invoke-Update {
    Assert-Admin
    $r = Test-Update
    if (-not $r -or -not $r.HasUpdate) { return }
    Write-Host ''
    $a = Read-Host '? Apply update now? [Y/n]'
    if ($a -and $a.ToLower() -notin @('y','yes','')) { Write-Host 'Skipped.'; return }
    $dir = Get-InstallDir
    if (Test-Path (Join-Path $dir '.git')) {
        Write-Host "Fetching origin/main..." -ForegroundColor DarkGray
        git -C $dir fetch --quiet --depth=1 origin main
        git -C $dir reset --hard origin/main
    } else {
        Write-Host "No git checkout at $dir - re-running bootstrap" -ForegroundColor Yellow
        Invoke-Expression (Invoke-WebRequest -Uri "$($Script:RepoRaw)/bootstrap.ps1" -UseBasicParsing).Content
        return
    }
    Write-Host 'Re-running install.ps1 (full install)...' -ForegroundColor DarkGray
    & (Join-Path $dir 'install.ps1')
    Write-Host 'Update complete.' -ForegroundColor Green
}

function Show-Bans {
    param([switch]$Top, [switch]$Geo, [int]$Hours = 24)

    Write-Host "Failed logons (Security 4625) last $Hours h:" -ForegroundColor DarkGray
    $events = @()
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName='Security'; ID=4625; StartTime=(Get-Date).AddHours(-$Hours)
        } -ErrorAction Stop
    } catch {
        Write-Host '  (Security log empty or auditing disabled - run module 03-rdp.ps1)' -ForegroundColor Yellow
    }

    if ($events) {
        $rows = $events | ForEach-Object {
            $ip = $_.Properties[19].Value
            if (-not $ip -or $ip -eq '-') { $ip = 'local' }
            [PSCustomObject]@{
                Time   = $_.TimeCreated
                User   = $_.Properties[5].Value
                Source = $ip
            }
        }
        $grouped = $rows | Group-Object Source | Sort-Object Count -Descending
        Write-Host ('  Distinct sources: {0}   Total attempts: {1}' -f $grouped.Count, $rows.Count)
        Write-Host ''
        $list = if ($Top) { $grouped | Select-Object -First 20 } else { $grouped }
        $list | ForEach-Object {
            $first = ($_.Group | Sort-Object Time | Select-Object -First 1).Time
            $last  = ($_.Group | Sort-Object Time | Select-Object -Last  1).Time
            $usrs  = ($_.Group.User | Sort-Object -Unique) -join ','
            [PSCustomObject]@{
                Source  = $_.Name
                Count   = $_.Count
                Users   = $usrs
                First   = $first
                Last    = $last
            }
        } | Format-Table -AutoSize
    }

    Write-Host ''
    Write-Host 'Firewall blocks (DDoS-Protect rule group, last 24h):' -ForegroundColor DarkGray
    try {
        # Security event 5152 = WFP block. Filter to our rules by name.
        $blocks = Get-WinEvent -FilterHashtable @{LogName='Security';ID=5152;StartTime=(Get-Date).AddHours(-24)} -ErrorAction SilentlyContinue
        if ($blocks) {
            $ours = $blocks | Where-Object { $_.Message -match 'DDoS-Protect' }
            Write-Host ("  Blocked packets: {0}" -f $ours.Count)
        } else {
            Write-Host '  (WFP audit logging not enabled - auditpol /set /subcategory:"Filtering Platform Packet Drop" /failure:enable)' -ForegroundColor DarkGray
        }
    } catch { }

    Write-Host ''
    Write-Host ("Active rules in 'DDoS-Protect' group: {0}" -f `
        (Get-NetFirewallRule -Group 'DDoS-Protect' -ErrorAction SilentlyContinue | Where-Object Enabled).Count) -ForegroundColor DarkGray

    if ($Geo -and $events) {
        Write-Host ''
        Write-Host 'GeoIP (ip-api.com free tier):' -ForegroundColor DarkGray
        $unique = $grouped.Name | Where-Object { $_ -ne 'local' -and $_ -notmatch '^127\.' -and $_ -notmatch '^10\.' -and $_ -notmatch '^192\.168\.' } | Select-Object -First 25
        foreach ($ip in $unique) {
            try {
                $r = Invoke-RestMethod -Uri "http://ip-api.com/json/$ip`?fields=country,countryCode,isp,city" -TimeoutSec 4
                "  {0,-18} {1,-3} {2,-25} {3}" -f $ip, $r.countryCode, $r.isp, $r.city
            } catch { "  $ip  (lookup failed)" }
            Start-Sleep -Milliseconds 300
        }
    }
}

function Show-Stats {
    Show-Status
    Write-Host ''
    $sample = Join-Path $env:ProgramData 'ddos-protect\state\last-sample.json'
    if (Test-Path $sample) {
        Write-Host 'Last watcher sample:' -ForegroundColor DarkGray
        Get-Content -Raw $sample | ConvertFrom-Json | Format-List
    }
    Write-Host 'Top 10 foreign IPs by established connections:' -ForegroundColor DarkGray
    Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Where-Object RemoteAddress -notmatch '^(127\.|0\.0\.0\.0|::|fe80)' |
        Group-Object RemoteAddress |
        Sort-Object Count -Descending |
        Select-Object -First 10 |
        Format-Table @{n='IP';e={$_.Name}}, Count -AutoSize
}

function Add-Ban {
    param([string]$Ip)
    if (-not $Ip) { Write-Host 'usage: ddos-protect ban <ip>' -ForegroundColor Red; return }
    Assert-Admin
    New-NetFirewallRule -DisplayName "DDoS-Protect Manual ban $Ip" `
        -Group 'DDoS-Protect' -Direction Inbound -Action Block `
        -RemoteAddress $Ip -Profile Any | Out-Null
    Write-Host "Banned $Ip" -ForegroundColor Green
}
function Remove-Ban {
    param([string]$Ip)
    if (-not $Ip) { Write-Host 'usage: ddos-protect unban <ip>' -ForegroundColor Red; return }
    Assert-Admin
    Get-NetFirewallRule -Group 'DDoS-Protect' -ErrorAction SilentlyContinue |
        Where-Object { (Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $_).RemoteAddress -contains $Ip } |
        Remove-NetFirewallRule
    Write-Host "Unbanned $Ip" -ForegroundColor Green
}

switch ($Command.ToLower()) {
    'on' {
        Assert-Admin
        Set-FwState   -Enabled $true
        Set-TaskState 'DDoS-Protect Watcher'     -Enabled $true
        Set-TaskState 'DDoS-Protect Audit Burst' -Enabled $true
        Write-Host 'ddos-protect: ON' -ForegroundColor Green
        Show-Status
    }
    'off' {
        Assert-Admin
        Set-FwState   -Enabled $false
        Set-TaskState 'DDoS-Protect Watcher'     -Enabled $false
        Set-TaskState 'DDoS-Protect Audit Burst' -Enabled $false
        Write-Host 'ddos-protect: OFF' -ForegroundColor Yellow
        Write-Host '(configs untouched - run "ddos-protect on" to re-enable, or uninstall.ps1 to remove)' -ForegroundColor DarkGray
    }
    'restart' {
        Assert-Admin
        & $PSCommandPath off
        & $PSCommandPath on
    }
    { $_ -in 'status','' } {
        Show-Status
    }
    'bans' {
        $top = $args -contains '--top'
        $geo = $args -contains '--geo'
        Show-Bans -Top:$top -Geo:$geo
    }
    'stats' { Show-Stats }
    'ban'   { Add-Ban   ($args | Select-Object -First 1) }
    'unban' { Remove-Ban ($args | Select-Object -First 1) }
    { $_ -in 'version','-v','--version' } { Show-Version }
    'update-check' { Test-Update | Out-Null }
    'update'       { Invoke-Update }
    { $_ -in 'help','-h','--help','/?' } {
        @'
Usage: ddos-protect <command>

  on             Enable Windows Firewall rules + watcher + 4625 alert task
  off            Disable everything (configs untouched)
  status         Show component state
  restart        off then on
  bans           Failed logons last 24h grouped by source IP + firewall blocks
  bans --top     Top 20 sources by failure count
  bans --geo     Add GeoIP/ISP per source (ip-api.com free tier)
  stats          Detailed: last watcher sample + top connected peers
  ban <ip>       Add a manual block rule to the DDoS-Protect group
  unban <ip>     Remove any DDoS-Protect rule matching that IP
  version        Show installed version
  update-check   Check GitHub CHANGELOG.md for a newer release
  update         Check, then git pull + re-run install.ps1 if newer is available

Components controlled:
  - Windows Firewall rules tagged Group "DDoS-Protect"
  - Scheduled Task "DDoS-Protect Watcher" (realtime CPU/Mem/Net/TCP monitor)
  - Scheduled Task "DDoS-Protect Audit Burst" (4625 logon-flood alert)

For Cloudflare Under Attack mode:   ddos-cf.ps1 on / off
For ad-hoc notifications:           ddos-notify "title" "msg"
For permanent removal:              uninstall.ps1
'@
    }
    default {
        Write-Host "unknown command: $Command" -ForegroundColor Red
        & $PSCommandPath help
        exit 2
    }
}
