# install.ps1 - Windows entrypoint.
# Detects installed services, presents menu, runs selected modules, records snapshot.

$ErrorActionPreference = 'Stop'
$Script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Script:ScriptRoot 'lib\ui.ps1')
. (Join-Path $Script:ScriptRoot 'lib\detect.ps1')

Assert-Administrator
Show-Banner

$StateDir  = Join-Path $Script:ScriptRoot 'windows\restore'
$StateFile = Join-Path $StateDir 'state.json'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

$winInfo = Get-WindowsVersionInfo
$services = Get-DetectedServices

Write-Log info "OS:       $($winInfo.Caption) (build $($winInfo.Build))"
Write-Log info "Arch:     $($winInfo.Architecture)"
Write-Log info "Services: $(if ($services) { $services -join ', ' } else { '<none detected>' })"

if (-not (Test-Path $StateFile)) {
    @{
        version      = $Script:DDOS_VERSION
        os           = 'windows'
        build        = $winInfo.Build
        host         = $env:COMPUTERNAME
        installed_at = (Get-Date).ToUniversalTime().ToString('o')
        modules      = @()
        tcpip        = @{}
        services     = @{}
        debloat      = @{ removed = @() }
        firewall     = @{ group = 'DDoS-Protect' }
    } | ConvertTo-Json -Depth 6 | Set-Content -Path $StateFile -Encoding UTF8
}

$env:DDOS_STATE_FILE = $StateFile
$env:DDOS_SCRIPT_DIR = $Script:ScriptRoot

$Modules = @(
    @{ File='01-firewall.ps1';   Desc='Windows Firewall + rate limit + amp-port blackhole' },
    @{ File='02-tcpip.ps1';      Desc='TCP/IP stack hardening (SYN attack protect, ICMP redirect, source routing)' },
    @{ File='03-rdp.ps1';        Desc='RDP brute-force lockout + NLA enforce' },
    @{ File='04-mysql.ps1';      Desc='MySQL/MariaDB hardening (if installed)' },
    @{ File='05-debloat.ps1';    Desc='Debloat UWP apps (Candy Crush, Bing, Xbox, Skype, ...) - reversible' },
    @{ File='06-telemetry.ps1';  Desc='Disable Microsoft telemetry services + block telemetry endpoints' },
    @{ File='07-defender.ps1';   Desc='Defender hardening + quick scan + tamper protection' },
    @{ File='08-audit.ps1';      Desc='Audit autorun, services, scheduled tasks, listening ports' },
    @{ File='09-unsafe-services.ps1'; Desc='Disable SMBv1, Remote Registry, Remote Access, etc.' },
    @{ File='10-cloudflare.ps1'; Desc='Cloudflare integration (under-attack mode + ban sync)' },
    @{ File='11-notify.ps1';     Desc='Configure notifications (Discord / Telegram / ntfy / Slack / webhook)' },
    @{ File='12-monitor.ps1';    Desc='Realtime watchdog (CPU/RAM/network/conn) + auto-alert' }
)

function Invoke-Module {
    param([hashtable]$Mod)
    Write-Step $Mod.Desc
    $path = Join-Path $Script:ScriptRoot "windows\modules\$($Mod.File)"
    if (-not (Test-Path $path)) {
        Write-Fail "module not found: $($Mod.File)"
        return
    }
    try {
        & $path
        Write-Ok "$($Mod.File) complete"
    } catch {
        Write-Fail "$($Mod.File) failed: $_"
    }
}

function Show-MainMenu {
    $opts = @(
        'Full install (all modules)'
        'Choose modules'
        'Dry-run (print what would happen)'
        'Uninstall / restore'
        'Exit'
    )
    Read-MenuChoice -Title 'Main menu' -Options $opts
}

while ($true) {
    $choice = Show-MainMenu
    switch ($choice) {
        1 {
            foreach ($m in $Modules) { Invoke-Module $m }
            Write-Ok "All modules attempted. State recorded at $StateFile"
            break
        }
        2 {
            $labels = $Modules | ForEach-Object { $_.Desc }
            $picks  = Read-MultiMenu -Title 'Select modules to run' -Options $labels
            foreach ($i in $picks) { Invoke-Module $Modules[$i-1] }
            Write-Ok "Selected modules attempted. State recorded at $StateFile"
            break
        }
        3 {
            Write-Step 'Dry-run'
            foreach ($m in $Modules) { Write-Note "would run: $($m.File) - $($m.Desc)" }
        }
        4 {
            Write-Log info 'Running uninstaller...'
            & (Join-Path $Script:ScriptRoot 'uninstall.ps1')
            exit 0
        }
        5 {
            Write-Log info 'Exit.'
            exit 0
        }
    }
    if ($choice -eq 1 -or $choice -eq 2) { break }
}

# Install master switch into %ProgramData% + add a CMD shim on PATH.
$ctlSrc = Join-Path $Script:ScriptRoot 'scripts\ddos-protect.ps1'
$ctlDir = Join-Path $env:ProgramData 'ddos-protect'
New-Item -ItemType Directory -Force -Path $ctlDir | Out-Null
Copy-Item -Force $ctlSrc (Join-Path $ctlDir 'ddos-protect.ps1')
$shimDir = "$env:SystemRoot\System32"
@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%ProgramData%\ddos-protect\ddos-protect.ps1" %*
"@ | Set-Content -Path (Join-Path $shimDir 'ddos-protect.cmd') -Encoding ASCII
@"
$Script:DDOS_VERSION
$Script:ScriptRoot
"@ | Set-Content -Path (Join-Path $ctlDir 'version') -Encoding ASCII
Write-Note "Master switch installed: ddos-protect on | off | status | bans | update"
Write-Note "Installed version v$Script:DDOS_VERSION"
