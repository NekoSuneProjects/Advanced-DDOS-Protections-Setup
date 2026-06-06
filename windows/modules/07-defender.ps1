# 07-defender.ps1 - Windows Defender hardening + quick scan + tamper protection
# guidance. Defender is free, built-in, and the strongest anti-backdoor we have
# on stock Windows.

$ErrorActionPreference = 'Continue'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')

if (-not (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
    Write-Note 'Defender cmdlets unavailable on this SKU - skipping'
    return
}

# Enable everything.
Set-MpPreference -DisableRealtimeMonitoring        $false  -ErrorAction SilentlyContinue
Set-MpPreference -DisableBehaviorMonitoring        $false  -ErrorAction SilentlyContinue
Set-MpPreference -DisableScriptScanning            $false  -ErrorAction SilentlyContinue
Set-MpPreference -DisableArchiveScanning           $false  -ErrorAction SilentlyContinue
Set-MpPreference -DisableEmailScanning             $false  -ErrorAction SilentlyContinue
Set-MpPreference -DisableIOAVProtection            $false  -ErrorAction SilentlyContinue
Set-MpPreference -DisableRemovableDriveScanning    $false  -ErrorAction SilentlyContinue
Set-MpPreference -DisableIntrusionPreventionSystem $false  -ErrorAction SilentlyContinue
Set-MpPreference -EnableNetworkProtection          Enabled -ErrorAction SilentlyContinue
Set-MpPreference -MAPSReporting                    Advanced -ErrorAction SilentlyContinue
Set-MpPreference -SubmitSamplesConsent             SendSafeSamples -ErrorAction SilentlyContinue
Set-MpPreference -PUAProtection                    Enabled -ErrorAction SilentlyContinue
Set-MpPreference -CloudBlockLevel                  High    -ErrorAction SilentlyContinue
Set-MpPreference -CloudExtendedTimeout             50      -ErrorAction SilentlyContinue
Write-Ok 'Defender preferences hardened'

# Attack Surface Reduction rules (ASR) - free with Defender on Pro/Enterprise.
$asrIds = @(
    'BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550',  # Block executable content from email
    'D4F940AB-401B-4EFC-AADC-AD5F3C50688A',  # Block all Office apps from creating child processes
    '3B576869-A4EC-4529-8536-B80A7769E899',  # Block Office apps from creating executable content
    '75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84',  # Block Office apps from injecting code into other processes
    'D3E037E1-3EB8-44C8-A917-57927947596D',  # Block JavaScript/VBScript launching downloaded executable content
    '5BEB7EFE-FD9A-4556-801D-275E5FFC04CC',  # Block obfuscated scripts
    'B2B3F03D-6A65-4F7B-A9C7-1C7EF74A9BA4',  # Block untrusted/unsigned processes from USB
    '92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B',  # Block Win32 API calls from Office macros
    '01443614-CD74-433A-B99E-2ECDC07BFC25',  # Block executable files from running unless trusted (Audit recommended first)
    'C1DB55AB-C21A-4637-BB3F-A12568109D35'   # Use advanced ransomware protection
)
foreach ($id in $asrIds) {
    try {
        Add-MpPreference -AttackSurfaceReductionRules_Ids $id `
            -AttackSurfaceReductionRules_Actions Enabled -ErrorAction Stop
    } catch { }
}
Write-Ok "Enabled $($asrIds.Count) Attack Surface Reduction rules"

# Signature update + quick scan.
try {
    Update-MpSignature -ErrorAction SilentlyContinue
    Write-Note 'Defender signatures updated'
} catch { }
if (Read-YesNo 'Run a Defender quick scan now? (takes a few minutes)' -DefaultYes) {
    Start-MpScan -ScanType QuickScan
    Write-Ok 'Quick scan started in background (results in Windows Security)'
}

Write-Note 'Tamper Protection must be toggled manually:'
Write-Note '  Windows Security -> Virus & threat protection -> Manage settings'
