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
    { $_ -in 'help','-h','--help','/?' } {
        @'
Usage: ddos-protect <command>

  on         Enable Windows Firewall rules + watcher + 4625 alert task
  off        Disable everything (configs untouched)
  status     Show component state
  restart    off then on

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
