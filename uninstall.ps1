# uninstall.ps1 - Reverses changes made by install.ps1 using state.json snapshot.

$ErrorActionPreference = 'Continue'
$Script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Script:ScriptRoot 'lib\ui.ps1')
. (Join-Path $Script:ScriptRoot 'lib\detect.ps1')

Assert-Administrator
Show-Banner

$StateFile = Join-Path $Script:ScriptRoot 'windows\restore\state.json'
$state = $null
if (Test-Path $StateFile) {
    $state = Get-Content -Raw -Path $StateFile | ConvertFrom-Json
} else {
    Write-Log warn "No state.json found at $StateFile."
    Write-Log warn 'Best-effort cleanup: removing DDoS-Protect firewall group, '
    Write-Log warn 're-enabling commonly-disabled telemetry services.'
    if (-not (Read-YesNo 'Proceed with best-effort uninstall?')) { exit 1 }
}

# 1) Remove firewall rules.
Write-Step 'Removing Windows Firewall rules tagged DDoS-Protect'
try {
    $rules = Get-NetFirewallRule -Group 'DDoS-Protect' -ErrorAction SilentlyContinue
    if ($rules) {
        $rules | Remove-NetFirewallRule
        Write-Ok "Removed $($rules.Count) firewall rules"
    } else { Write-Note 'No rules in DDoS-Protect group' }
} catch { Write-Fail "Firewall removal failed: $_" }

# 2) Restore TCP/IP registry values.
Write-Step 'Restoring TCP/IP registry values'
$tcpipKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
if ($state -and $state.tcpip) {
    foreach ($prop in $state.tcpip.PSObject.Properties) {
        try {
            if ($prop.Value -eq '__delete__') {
                Remove-ItemProperty -Path $tcpipKey -Name $prop.Name -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -Path $tcpipKey -Name $prop.Name -Value $prop.Value
            }
            Write-Ok "Restored Tcpip\$($prop.Name) -> $($prop.Value)"
        } catch { Write-Fail "Restore $($prop.Name) failed: $_" }
    }
} else { Write-Note 'No TCP/IP snapshot to restore' }

# 3) Re-enable services that were disabled.
Write-Step 'Restoring services'
if ($state -and $state.services) {
    foreach ($prop in $state.services.PSObject.Properties) {
        $svcName = $prop.Name
        $previousStartType = $prop.Value
        try {
            Set-Service -Name $svcName -StartupType $previousStartType -ErrorAction Stop
            if ($previousStartType -in @('Automatic','Manual')) {
                Start-Service -Name $svcName -ErrorAction SilentlyContinue
            }
            Write-Ok "$svcName -> $previousStartType"
        } catch { Write-Fail "Service $svcName restore failed: $_" }
    }
} else { Write-Note 'No services snapshot' }

# 4) Re-register debloated UWP apps for current user.
Write-Step 'Re-registering removed UWP apps'
if ($state -and $state.debloat -and $state.debloat.removed) {
    foreach ($pkg in $state.debloat.removed) {
        try {
            $manifest = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter 'AppXManifest.xml' -Recurse -ErrorAction SilentlyContinue |
                        Where-Object { $_.FullName -match [regex]::Escape($pkg) } | Select-Object -First 1
            if ($manifest) {
                Add-AppxPackage -Register $manifest.FullName -DisableDevelopmentMode -ErrorAction Stop
                Write-Ok "Re-registered $pkg"
            } else {
                Write-Note "$pkg manifest not on disk - install from Microsoft Store"
            }
        } catch { Write-Fail "$pkg re-register failed: $_" }
    }
} else { Write-Note 'No UWP apps to re-register' }

# 5) Strip ddos-protect helper bin (Cloudflare / Notify / Master switch).
Write-Step 'Removing helper scripts'
Remove-Item -Force "$env:SystemRoot\System32\ddos-protect.cmd" -ErrorAction SilentlyContinue
$bin = Join-Path $env:ProgramData 'ddos-protect'
if (Test-Path $bin) {
    Remove-Item $bin -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Removed $bin"
}

# 6) Restore Defender baseline if module 07 changed settings.
Write-Step 'Restoring Defender preferences'
try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    Write-Ok 'Defender realtime monitoring on'
} catch { Write-Note 'Defender preferences unchanged' }

# 7) Archive state file.
if (Test-Path $StateFile) {
    $archived = "$StateFile.uninstalled-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Move-Item -Path $StateFile -Destination $archived -Force
    Write-Note "State archive: $archived"
}

Write-Host ''
Write-Ok 'Uninstall complete.'
Write-Note 'Reboot recommended so registry and service changes take full effect.'
