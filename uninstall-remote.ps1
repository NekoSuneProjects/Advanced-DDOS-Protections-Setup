# uninstall-remote.ps1 - one-liner reversal.
# irm https://raw.githubusercontent.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup/main/uninstall-remote.ps1 | iex
$ErrorActionPreference = 'Stop'
$Prefix = if ($env:DDOS_PREFIX) { $env:DDOS_PREFIX } else { Join-Path $env:ProgramData 'ddos-protect-src' }
if (-not (Test-Path (Join-Path $Prefix 'uninstall.ps1'))) {
    Write-Error "No install found at $Prefix"
    exit 1
}
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& (Join-Path $Prefix 'uninstall.ps1')
