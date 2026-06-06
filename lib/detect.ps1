# lib/detect.ps1 - Windows version and service detection.

function Get-WindowsVersionInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    [PSCustomObject]@{
        Caption       = $os.Caption
        Version       = $os.Version
        Build         = $os.BuildNumber
        Architecture  = $os.OSArchitecture
        IsWindows11   = ([int]$os.BuildNumber -ge 22000)
        IsServer      = ($os.ProductType -ne 1)
    }
}

function Test-ServiceInstalled {
    param([Parameter(Mandatory)][string]$Name)
    [bool](Get-Service -Name $Name -ErrorAction SilentlyContinue)
}

function Test-IISInstalled {
    Test-ServiceInstalled -Name 'W3SVC'
}

function Test-MSSQLInstalled {
    $svcs = Get-Service -Name 'MSSQL*' -ErrorAction SilentlyContinue
    [bool]$svcs
}

function Test-MySQLInstalled {
    $svcs = Get-Service -Name 'MySQL*','MariaDB*' -ErrorAction SilentlyContinue
    [bool]$svcs
}

function Test-RDPEnabled {
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $v = Get-ItemProperty -Path $key -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue
    # 0 means RDP is enabled.
    return ($null -ne $v -and $v.fDenyTSConnections -eq 0)
}

function Get-DetectedServices {
    $found = @()
    if (Test-IISInstalled)    { $found += 'IIS' }
    if (Test-MySQLInstalled)  { $found += 'MySQL/MariaDB' }
    if (Test-MSSQLInstalled)  { $found += 'MSSQL' }
    if (Test-RDPEnabled)      { $found += 'RDP' }
    if (Test-ServiceInstalled -Name 'OpenSSH*') { $found += 'OpenSSH' }
    if (Test-ServiceInstalled -Name 'Apache*')  { $found += 'Apache' }
    if (Test-ServiceInstalled -Name 'nginx*')   { $found += 'nginx' }
    return $found
}

function Get-FirewallStatus {
    Get-NetFirewallProfile | ForEach-Object {
        [PSCustomObject]@{
            Profile = $_.Name
            Enabled = $_.Enabled
        }
    }
}
