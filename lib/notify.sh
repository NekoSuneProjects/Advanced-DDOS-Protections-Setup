#!/usr/bin/env bash
# lib/notify.sh — multi-channel notification helper.
# Reads /etc/ddos-protect/notify.env (set by module 13-notify.sh).
# Usage: send_notification "title" "message" [severity]
#   severity: info | warn | critical (default: info)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "lib/notify.sh is a library; source it, don't execute it." >&2
    exit 1
fi

NOTIFY_CONF="${NOTIFY_CONF:-/etc/ddos-protect/notify.env}"

_load_notify_conf() {
    [[ -r "$NOTIFY_CONF" ]] || return 0
    set -a; . "$NOTIFY_CONF"; set +a
}

_notify_discord() {
    local title="$1" message="$2" sev="$3"
    [[ -z "${DISCORD_WEBHOOK_URL:-}" ]] && return 0
    local color
    case "$sev" in
        critical) color=15158332 ;;  # red
        warn)     color=15844367 ;;  # yellow
        *)        color=3447003  ;;  # blue
    esac
    local payload
    payload=$(cat <<JSON
{"embeds":[{"title":"${title}","description":"${message}","color":${color},"footer":{"text":"$(hostname) · ddos-protect"}}]}
JSON
)
    curl -sS -m 8 -H 'Content-Type: application/json' -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1 || return 1
}

_notify_telegram() {
    local title="$1" message="$2" sev="$3"
    [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
    local icon
    case "$sev" in critical) icon='🚨';; warn) icon='⚠️';; *) icon='ℹ️';; esac
    local text="${icon} *${title}*
${message}
_$(hostname)_"
    curl -sS -m 8 \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "parse_mode=Markdown" \
        --data-urlencode "text=${text}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" >/dev/null 2>&1 || return 1
}

_notify_ntfy() {
    local title="$1" message="$2" sev="$3"
    [[ -z "${NTFY_TOPIC:-}" ]] && return 0
    local server="${NTFY_SERVER:-https://ntfy.sh}"
    local prio
    case "$sev" in critical) prio=5;; warn) prio=4;; *) prio=3;; esac
    curl -sS -m 8 \
        -H "Title: ${title}" \
        -H "Priority: ${prio}" \
        -H "Tags: shield" \
        -d "${message}" \
        "${server}/${NTFY_TOPIC}" >/dev/null 2>&1 || return 1
}

_notify_slack() {
    local title="$1" message="$2" sev="$3"
    [[ -z "${SLACK_WEBHOOK_URL:-}" ]] && return 0
    local color
    case "$sev" in critical) color='danger';; warn) color='warning';; *) color='good';; esac
    local payload
    payload=$(cat <<JSON
{"attachments":[{"title":"${title}","text":"${message}","color":"${color}","footer":"$(hostname) · ddos-protect"}]}
JSON
)
    curl -sS -m 8 -H 'Content-Type: application/json' -d "$payload" "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || return 1
}

_notify_gotify() {
    local title="$1" message="$2" sev="$3"
    [[ -z "${GOTIFY_URL:-}" || -z "${GOTIFY_TOKEN:-}" ]] && return 0
    local prio
    case "$sev" in critical) prio=8;; warn) prio=5;; *) prio=3;; esac
    curl -sS -m 8 \
        -F "title=${title}" \
        -F "message=${message}" \
        -F "priority=${prio}" \
        "${GOTIFY_URL%/}/message?token=${GOTIFY_TOKEN}" >/dev/null 2>&1 || return 1
}

_notify_webhook() {
    # generic JSON POST
    local title="$1" message="$2" sev="$3"
    [[ -z "${GENERIC_WEBHOOK_URL:-}" ]] && return 0
    local payload
    payload=$(cat <<JSON
{"host":"$(hostname)","title":"${title}","message":"${message}","severity":"${sev}","timestamp":"$(date -u +%FT%TZ)"}
JSON
)
    curl -sS -m 8 -H 'Content-Type: application/json' -d "$payload" "$GENERIC_WEBHOOK_URL" >/dev/null 2>&1 || return 1
}

send_notification() {
    local title="${1:-DDoS-Protect}"
    local message="${2:-}"
    local sev="${3:-info}"
    _load_notify_conf
    _notify_discord  "$title" "$message" "$sev" &
    _notify_telegram "$title" "$message" "$sev" &
    _notify_ntfy     "$title" "$message" "$sev" &
    _notify_slack    "$title" "$message" "$sev" &
    _notify_gotify   "$title" "$message" "$sev" &
    _notify_webhook  "$title" "$message" "$sev" &
    wait
    return 0
}
