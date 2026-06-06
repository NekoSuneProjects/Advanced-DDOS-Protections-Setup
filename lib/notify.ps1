# lib/notify.ps1 - multi-channel notification helper for Windows.
# Reads $env:ProgramData\ddos-protect\notify.json (set by 11-notify.ps1).
# Usage: Send-DDoSNotification -Title 't' -Message 'm' [-Severity info|warn|critical]

function Get-NotifyConfig {
    $path = Join-Path $env:ProgramData 'ddos-protect\notify.json'
    if (Test-Path $path) {
        try { return (Get-Content -Raw $path | ConvertFrom-Json) } catch { return $null }
    }
    return $null
}

function Send-DDoSNotification {
    [CmdletBinding()]
    param(
        [string]$Title = 'DDoS-Protect',
        [string]$Message = '',
        [ValidateSet('info','warn','critical')]
        [string]$Severity = 'info'
    )

    $cfg = Get-NotifyConfig
    if (-not $cfg) { return }
    $host_ = $env:COMPUTERNAME

    # ---- Discord ----
    if ($cfg.DiscordWebhookUrl) {
        $color = switch ($Severity) { 'critical'{15158332} 'warn'{15844367} default{3447003} }
        $body = @{
            embeds = @(@{
                title       = $Title
                description = $Message
                color       = $color
                footer      = @{ text = "$host_ . ddos-protect" }
            })
        } | ConvertTo-Json -Depth 5 -Compress
        try {
            Invoke-RestMethod -Uri $cfg.DiscordWebhookUrl -Method Post `
                -ContentType 'application/json' -Body $body -TimeoutSec 8 | Out-Null
        } catch {}
    }

    # ---- Telegram ----
    if ($cfg.TelegramBotToken -and $cfg.TelegramChatId) {
        $icon = switch ($Severity) { 'critical'{'[CRITICAL]'} 'warn'{'[WARN]'} default{'[INFO]'} }
        $text = "$icon *$Title*`n$Message`n_$host_ _"
        $uri = "https://api.telegram.org/bot$($cfg.TelegramBotToken)/sendMessage"
        try {
            Invoke-RestMethod -Uri $uri -Method Post -TimeoutSec 8 -Body @{
                chat_id    = $cfg.TelegramChatId
                parse_mode = 'Markdown'
                text       = $text
            } | Out-Null
        } catch {}
    }

    # ---- ntfy.sh ----
    if ($cfg.NtfyTopic) {
        $server = if ($cfg.NtfyServer) { $cfg.NtfyServer } else { 'https://ntfy.sh' }
        $prio = switch ($Severity) { 'critical'{5} 'warn'{4} default{3} }
        try {
            Invoke-RestMethod -Uri "$server/$($cfg.NtfyTopic)" -Method Post `
                -Headers @{ Title=$Title; Priority="$prio"; Tags='shield' } `
                -Body $Message -TimeoutSec 8 | Out-Null
        } catch {}
    }

    # ---- Slack ----
    if ($cfg.SlackWebhookUrl) {
        $color = switch ($Severity) { 'critical'{'danger'} 'warn'{'warning'} default{'good'} }
        $body = @{
            attachments = @(@{
                title  = $Title
                text   = $Message
                color  = $color
                footer = "$host_ . ddos-protect"
            })
        } | ConvertTo-Json -Depth 5 -Compress
        try {
            Invoke-RestMethod -Uri $cfg.SlackWebhookUrl -Method Post `
                -ContentType 'application/json' -Body $body -TimeoutSec 8 | Out-Null
        } catch {}
    }

    # ---- Gotify ----
    if ($cfg.GotifyUrl -and $cfg.GotifyToken) {
        $prio = switch ($Severity) { 'critical'{8} 'warn'{5} default{3} }
        try {
            Invoke-RestMethod -Uri "$($cfg.GotifyUrl.TrimEnd('/'))/message?token=$($cfg.GotifyToken)" `
                -Method Post -TimeoutSec 8 -Body @{
                    title=$Title; message=$Message; priority=$prio
                } | Out-Null
        } catch {}
    }

    # ---- Generic webhook ----
    if ($cfg.GenericWebhookUrl) {
        $body = @{
            host      = $host_
            title     = $Title
            message   = $Message
            severity  = $Severity
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json -Compress
        try {
            Invoke-RestMethod -Uri $cfg.GenericWebhookUrl -Method Post `
                -ContentType 'application/json' -Body $body -TimeoutSec 8 | Out-Null
        } catch {}
    }
}
