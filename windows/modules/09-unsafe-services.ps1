# 09-unsafe-services.ps1 - Disable historically-exploited Windows services.
# Each previous StartType is recorded in state.json so uninstall.ps1 puts it back.

$ErrorActionPreference = 'Continue'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')

$StateFile = $env:DDOS_STATE_FILE
$state = Get-Content -Raw $StateFile | ConvertFrom-Json
if (-not $state.services) { $state | Add-Member -NotePropertyName services -NotePropertyValue (New-Object PSObject) -Force }

# Service -> reason. Asks per service.
$candidates = @(
    @{Name='RemoteRegistry';     Reason='Remote registry editing - unused on most desktops'},
    @{Name='SSDPSRV';            Reason='SSDP discovery - UPnP amp vector if exposed'},
    @{Name='upnphost';           Reason='UPnP device host'},
    @{Name='WMPNetworkSvc';      Reason='Windows Media Player network sharing'},
    @{Name='LLDP';               Reason='Link-Layer Discovery'},
    @{Name='LanmanWorkstation';  Reason='SMB client - keep enabled if you mount network shares'},
    @{Name='Browser';            Reason='Computer Browser (legacy SMB)'},
    @{Name='Fax';                Reason='Fax service'},
    @{Name='lfsvc';              Reason='Geolocation service'},
    @{Name='SharedAccess';       Reason='Internet Connection Sharing'},
    @{Name='WerSvc';             Reason='Windows Error Reporting'},
    @{Name='WSearch';            Reason='Windows Search indexing (heavy disk, optional)'},
    @{Name='XblAuthManager';     Reason='Xbox Live auth (gaming only)'},
    @{Name='XblGameSave';        Reason='Xbox Live save (gaming only)'},
    @{Name='XboxNetApiSvc';      Reason='Xbox networking'}
)

foreach ($c in $candidates) {
    $svc = Get-Service -Name $c.Name -ErrorAction SilentlyContinue
    if (-not $svc) { continue }
    if ($svc.StartType -eq 'Disabled') { continue }
    if (Read-YesNo ("  Disable {0}? ({1})" -f $c.Name, $c.Reason)) {
        $prev = (Get-WmiObject Win32_Service -Filter "Name='$($c.Name)'").StartMode
        if (-not $prev) { $prev = 'Manual' }
        Add-Member -InputObject $state.services -NotePropertyName $c.Name -NotePropertyValue $prev -Force
        try {
            Stop-Service -Name $c.Name -Force -ErrorAction SilentlyContinue
            Set-Service  -Name $c.Name -StartupType Disabled
            Write-Ok "  $($c.Name) disabled (was $prev)"
        } catch { Write-Fail "  $($c.Name): $_" }
    }
}

$state | ConvertTo-Json -Depth 6 | Set-Content -Path $StateFile -Encoding UTF8
Write-Ok 'Unsafe-services pass complete'
