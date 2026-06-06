# lib/ui.ps1 - colored TUI helpers for install.ps1 / uninstall.ps1 / modules.
# Dot-source: . "$PSScriptRoot\..\lib\ui.ps1"

$Script:DDOS_VERSION = '1.0.0'

function Show-Banner {
    $art = @'

   ___      __                            __
  / _ |____/ /  _____ ____  _______ ___  / /
 / __ / _  / |/ / _ `/ _ \/ __/ -_) _ \/ _/
/_/ |_\_,_/|___/\_,_/_//_/\__/\__/_//_/\__/
   ___  ___  ___  ___    ___           __        __
  / _ \/ _ \/ _ \(_-<   / _ \_______  / /____ __/ /_
 / // / // / // / __/  / ___/ __/ _ \/ __/ -_) __/ __/
/____/____/____/____/_/_/  /_/  \___/\__/\__/\__/\__/

'@
    Write-Host $art -ForegroundColor Cyan
    Write-Host "   Advanced DDoS Protections Setup  " -ForegroundColor White -NoNewline
    Write-Host "v$Script:DDOS_VERSION" -ForegroundColor DarkGray
    Write-Host "   Linux . macOS . Windows . defensive hardening toolkit" -ForegroundColor DarkGray
    Write-Host ''
}

function Write-Log {
    param(
        [ValidateSet('info','warn','err','ok')]
        [string]$Level,
        [Parameter(Mandatory, ValueFromRemainingArguments)]
        [string[]]$Message
    )
    $ts = (Get-Date -Format 'HH:mm:ss')
    switch ($Level) {
        'info' { $tag = 'INFO'; $color = 'Blue' }
        'warn' { $tag = 'WARN'; $color = 'Yellow' }
        'err'  { $tag = 'ERR '; $color = 'Red' }
        'ok'   { $tag = 'OK  '; $color = 'Green' }
    }
    Write-Host "[$ts] " -ForegroundColor DarkGray -NoNewline
    Write-Host "$tag " -ForegroundColor $color -NoNewline
    Write-Host ($Message -join ' ')
}

function Write-Step { param([string]$Msg)
    Write-Host ''
    Write-Host '> ' -ForegroundColor Cyan -NoNewline
    Write-Host $Msg -ForegroundColor White
}

function Write-Ok   { param([string]$Msg) Write-Host '  v ' -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Write-Fail { param([string]$Msg) Write-Host '  x ' -ForegroundColor Red -NoNewline; Write-Host $Msg }
function Write-Note { param([string]$Msg) Write-Host '  - ' -ForegroundColor DarkGray -NoNewline; Write-Host $Msg }

function Read-YesNo {
    param([string]$Prompt, [switch]$DefaultYes)
    $hint = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        Write-Host '? ' -ForegroundColor Magenta -NoNewline
        Write-Host "$Prompt " -NoNewline
        Write-Host $hint -ForegroundColor DarkGray -NoNewline
        Write-Host ' ' -NoNewline
        $a = (Read-Host).Trim().ToLower()
        if ([string]::IsNullOrEmpty($a)) {
            return [bool]$DefaultYes
        }
        switch ($a) {
            { $_ -in 'y','yes' } { return $true }
            { $_ -in 'n','no'  } { return $false }
            default { Write-Host '  Please answer y or n.' -ForegroundColor Yellow }
        }
    }
}

function Read-MenuChoice {
    param([string]$Title, [string[]]$Options)
    Write-Host ''
    Write-Host $Title -ForegroundColor White
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  $($i+1)) " -ForegroundColor Cyan -NoNewline
        Write-Host $Options[$i]
    }
    Write-Host ''
    while ($true) {
        Write-Host '> ' -ForegroundColor Magenta -NoNewline
        Write-Host "Choose [1-$($Options.Count)]: " -NoNewline
        $raw = Read-Host
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
            return $n
        }
        Write-Host '  Invalid choice.' -ForegroundColor Yellow
    }
}

function Read-MultiMenu {
    param([string]$Title, [string[]]$Options)
    Write-Host ''
    Write-Host "$Title  " -ForegroundColor White -NoNewline
    Write-Host '(comma-separated, e.g. 1,3,4 or "all")' -ForegroundColor DarkGray
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  $($i+1)) " -ForegroundColor Cyan -NoNewline
        Write-Host $Options[$i]
    }
    Write-Host ''
    while ($true) {
        Write-Host '> ' -ForegroundColor Magenta -NoNewline
        Write-Host 'Select: ' -NoNewline
        $raw = (Read-Host).Trim().Replace(' ','')
        if ($raw -eq 'all') { return (1..$Options.Count) }
        $parts = $raw -split ','
        $chosen = @()
        $valid = $true
        foreach ($p in $parts) {
            $n = 0
            if ([int]::TryParse($p, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
                $chosen += $n
            } else { $valid = $false; break }
        }
        if ($valid -and $chosen.Count -gt 0) { return $chosen }
        Write-Host '  Invalid selection.' -ForegroundColor Yellow
    }
}

function Assert-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log err 'This script must be run as Administrator.'
        Write-Note 'Right-click PowerShell -> "Run as administrator", then re-run.'
        exit 1
    }
}
