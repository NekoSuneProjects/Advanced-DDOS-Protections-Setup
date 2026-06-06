# 04-mysql.ps1 - MySQL/MariaDB hardening on Windows (only if installed).

$ErrorActionPreference = 'Stop'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\detect.ps1')

if (-not (Test-MySQLInstalled)) {
    Write-Note 'MySQL/MariaDB not installed - skipping'
    return
}

# Find the my.ini Windows uses.
$svc = Get-Service -Name 'MySQL*','MariaDB*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $svc) { Write-Note 'MySQL service not located'; return }

$svcQuery = sc.exe qc $svc.Name | Out-String
if ($svcQuery -match 'BINARY_PATH_NAME\s+:\s+(.+)') {
    $binPath = $Matches[1].Trim().Trim('"')
    if ($binPath -match '--defaults-file=([^"\s]+)') {
        $iniPath = $Matches[1].Trim('"')
    }
}
if (-not $iniPath -or -not (Test-Path $iniPath)) {
    # Common default locations.
    $candidates = @(
        'C:\ProgramData\MySQL\MySQL Server 8.0\my.ini',
        'C:\ProgramData\MySQL\MySQL Server 5.7\my.ini',
        'C:\Program Files\MariaDB\my.ini'
    )
    $iniPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $iniPath) { Write-Fail 'Could not locate my.ini'; return }

Write-Note "Editing $iniPath"
$backup = "$iniPath.ddos-backup"
if (-not (Test-Path $backup)) { Copy-Item $iniPath $backup }

# Helper: set or replace an ini key under [mysqld].
$ini = Get-Content $iniPath
$desired = @{
    'bind-address'          = '127.0.0.1'
    'skip-name-resolve'     = $null
    'local-infile'          = '0'
    'max_connections'       = '200'
    'max_user_connections'  = '30'
    'max_connect_errors'    = '100'
    'connect_timeout'       = '5'
}
$inSection = $false
$newLines = @()
$seen = @{}
foreach ($line in $ini) {
    if ($line -match '^\s*\[mysqld\]\s*$') { $inSection = $true;  $newLines += $line; continue }
    if ($line -match '^\s*\[.+\]\s*$' -and $inSection) {
        foreach ($k in $desired.Keys) {
            if (-not $seen[$k]) {
                $newLines += if ($null -eq $desired[$k]) { $k } else { "$k = $($desired[$k])" }
                $seen[$k] = $true
            }
        }
        $inSection = $false
    }
    if ($inSection) {
        $replaced = $false
        foreach ($k in $desired.Keys) {
            if ($line -match "^\s*$([regex]::Escape($k))\s*=") {
                $newLines += if ($null -eq $desired[$k]) { $k } else { "$k = $($desired[$k])" }
                $seen[$k] = $true; $replaced = $true; break
            } elseif ($line -match "^\s*$([regex]::Escape($k))\s*$" -and $null -eq $desired[$k]) {
                $newLines += $k; $seen[$k] = $true; $replaced = $true; break
            }
        }
        if (-not $replaced) { $newLines += $line }
    } else { $newLines += $line }
}
if ($inSection) {
    foreach ($k in $desired.Keys) {
        if (-not $seen[$k]) {
            $newLines += if ($null -eq $desired[$k]) { $k } else { "$k = $($desired[$k])" }
        }
    }
}
$newLines | Set-Content -Path $iniPath -Encoding ASCII

try {
    Restart-Service -Name $svc.Name -Force
    Write-Ok "$($svc.Name) restarted with hardened my.ini"
} catch {
    Write-Fail "Restart failed; rolling back: $_"
    Copy-Item $backup $iniPath -Force
}
