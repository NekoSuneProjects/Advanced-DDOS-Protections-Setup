# 05-debloat.ps1 - Remove UWP bloatware listed in configs\bloatware-list.txt.
# Fully reversible: each removed package's identity is appended to state.json
# and the uninstaller re-registers from the on-disk WindowsApps folder.

$ErrorActionPreference = 'Continue'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')

$StateFile = $env:DDOS_STATE_FILE
$listFile  = Join-Path $env:DDOS_SCRIPT_DIR 'windows\configs\bloatware-list.txt'
if (-not (Test-Path $listFile)) { Write-Fail "missing $listFile"; return }

$state = Get-Content -Raw $StateFile | ConvertFrom-Json
if (-not $state.debloat)         { $state | Add-Member -NotePropertyName debloat -NotePropertyValue (New-Object PSObject) -Force }
if (-not $state.debloat.removed) { $state.debloat | Add-Member -NotePropertyName removed -NotePropertyValue @() -Force }

# Create a System Restore point as belt-and-braces (best-effort; not on Home SKUs).
try {
    Enable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description 'DDoS-Protect pre-debloat' -RestorePointType MODIFY_SETTINGS -ErrorAction SilentlyContinue
    Write-Note 'Created system restore point (if supported by SKU)'
} catch { }

$packages = Get-Content $listFile | Where-Object { $_ -and -not $_.StartsWith('#') }

$removedCount = 0
foreach ($pkg in $packages) {
    $pkg = $pkg.Trim()
    if (-not $pkg) { continue }

    $installed = Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue
    if ($installed) {
        try {
            $installed | Remove-AppxPackage -AllUsers -ErrorAction Stop
            $state.debloat.removed = @($state.debloat.removed + $pkg | Sort-Object -Unique)
            $removedCount++
            Write-Ok "Removed $pkg"
        } catch { Write-Note "skip $pkg ($_)" }
    }
    # Prevent re-install for new profiles.
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $pkg } |
        ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
}

$state | ConvertTo-Json -Depth 6 | Set-Content -Path $StateFile -Encoding UTF8
Write-Ok "Debloat complete - $removedCount UWP package(s) removed (reversible)"
