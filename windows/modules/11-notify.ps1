# 11-notify.ps1 - configure notification channels and a scheduled task that
# fires alerts on high-severity Security/System events (4625 floods etc.)

$ErrorActionPreference = 'Stop'
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\ui.ps1')
. (Join-Path $env:DDOS_SCRIPT_DIR 'lib\notify.ps1')

$dataDir = Join-Path $env:ProgramData 'ddos-protect'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$confPath = Join-Path $dataDir 'notify.json'

# Load existing settings so re-runs don't wipe channels.
$cur = @{}
if (Test-Path $confPath) {
    $obj = Get-Content -Raw $confPath | ConvertFrom-Json
    $obj.PSObject.Properties | ForEach-Object { $cur[$_.Name] = $_.Value }
}

function Ask([string]$Label, [string]$Key) {
    $existing = $cur[$Key]
    $hint = if ($existing) { " [$existing]" } else { '' }
    $v = Read-Host "  $Label$hint"
    if ($v) { $cur[$Key] = $v }
}

Write-Note 'Configure notification channels. Leave blank to skip.'
Ask 'Discord webhook URL'      'DiscordWebhookUrl'
Ask 'Telegram bot token'       'TelegramBotToken'
Ask 'Telegram chat ID'         'TelegramChatId'
Ask 'ntfy.sh topic'            'NtfyTopic'
Ask 'ntfy server (https://ntfy.sh)' 'NtfyServer'
Ask 'Slack webhook URL'        'SlackWebhookUrl'
Ask 'Gotify URL'               'GotifyUrl'
Ask 'Gotify app token'         'GotifyToken'
Ask 'Generic webhook URL'      'GenericWebhookUrl'

$cur | ConvertTo-Json | Set-Content -Path $confPath -Encoding UTF8

# Lock down ACL.
$acl = Get-Acl $confPath
$acl.SetAccessRuleProtection($true, $false)
foreach ($id in @('SYSTEM','Administrators')) {
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $id, 'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl $confPath $acl
Write-Ok "Saved $confPath"

# Test fire.
if (Read-YesNo 'Send a test notification now?' -DefaultYes) {
    Send-DDoSNotification -Title 'DDoS-Protect test' `
        -Message "Hello from $env:COMPUTERNAME. All configured channels just got pinged." `
        -Severity info
    Write-Ok 'Test fired - check your channels'
}

# Scheduled task: watch for Security 4625 burst (>=15 failed logons in 1 minute).
$tName = 'DDoS-Protect Audit Burst'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -Command `". (Join-Path '$env:DDOS_SCRIPT_DIR' 'lib\notify.ps1'); `$e = Get-WinEvent -FilterHashtable @{LogName='Security';ID=4625;StartTime=(Get-Date).AddMinutes(-1)} -ErrorAction SilentlyContinue; if (`$e.Count -ge 15) { Send-DDoSNotification -Title 'Login flood' -Message ('{0} failed logons in 60s on {1}' -f `$e.Count, `$env:COMPUTERNAME) -Severity critical }`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger2 = New-ScheduledTaskTrigger -Once -At ([DateTime]::Now.AddMinutes(1)) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration ([TimeSpan]::FromDays(365000))
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Unregister-ScheduledTask -TaskName $tName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $tName -Action $action -Trigger @($trigger, $trigger2) `
    -Principal $principal -Description 'Watches Security event 4625 burst rate.' | Out-Null
Write-Ok "Scheduled task '$tName' installed (runs every 1m)"
