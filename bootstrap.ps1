# bootstrap.ps1 - one-liner Windows installer.
# Usage from an elevated PowerShell:
#   irm https://raw.githubusercontent.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup/main/bootstrap.ps1 | iex
# Source: https://github.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup
#
# What it does:
#   1. Verifies elevation
#   2. Clones the repo into C:\ProgramData\ddos-protect-src
#   3. Sets ExecutionPolicy Bypass for this process and runs install.ps1

$ErrorActionPreference = 'Stop'

$RepoUrl    = if ($env:DDOS_REPO)    { $env:DDOS_REPO }    else { 'https://github.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup.git' }
$RepoBranch = if ($env:DDOS_BRANCH)  { $env:DDOS_BRANCH }  else { 'main' }
$Prefix     = if ($env:DDOS_PREFIX)  { $env:DDOS_PREFIX }  else { Join-Path $env:ProgramData 'ddos-protect-src' }

# Elevation guard.
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Run this in an elevated PowerShell (right-click -> Run as administrator).'
    exit 1
}

# Need git.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host '[bootstrap] git not found - installing via winget'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Git.Git -e --silent --accept-source-agreements --accept-package-agreements
    } else {
        Write-Error 'Install git for Windows manually (https://git-scm.com), then re-run.'
        exit 1
    }
    $env:Path = "$env:Path;$env:ProgramFiles\Git\cmd"
}

if (Test-Path (Join-Path $Prefix '.git')) {
    Write-Host "[bootstrap] updating existing checkout at $Prefix"
    git -C $Prefix fetch --quiet --depth=1 origin $RepoBranch
    git -C $Prefix reset --hard "origin/$RepoBranch"
} else {
    Write-Host "[bootstrap] cloning $RepoUrl -> $Prefix"
    if (Test-Path $Prefix) { Remove-Item -Recurse -Force $Prefix }
    git clone --depth=1 --branch $RepoBranch $RepoUrl $Prefix
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& (Join-Path $Prefix 'install.ps1')
