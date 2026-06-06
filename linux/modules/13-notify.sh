#!/usr/bin/env bash
# 13-notify.sh — interactively configure notification channels.
# Result lands in /etc/ddos-protect/notify.env (mode 600).
# Also installs `ddos-notify` CLI for ad-hoc alerts and a fail2ban action
# that fires through every configured channel on every ban.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"

CONF=/etc/ddos-protect/notify.env
BIN=/usr/local/bin/ddos-notify
mkdir -p /etc/ddos-protect

# Load existing settings (so re-running this module doesn't wipe channels).
[[ -r "$CONF" ]] && { set -a; . "$CONF"; set +a; }

echo
note "Configure notification channels. Leave any blank to skip."
echo

read -rp "  Discord webhook URL          [${DISCORD_WEBHOOK_URL:-}]: " v;  [[ -n "$v" ]] && DISCORD_WEBHOOK_URL="$v"
read -rp "  Telegram bot token           [${TELEGRAM_BOT_TOKEN:-}]: " v;  [[ -n "$v" ]] && TELEGRAM_BOT_TOKEN="$v"
read -rp "  Telegram chat ID             [${TELEGRAM_CHAT_ID:-}]: "   v;  [[ -n "$v" ]] && TELEGRAM_CHAT_ID="$v"
read -rp "  ntfy.sh topic                [${NTFY_TOPIC:-}]: "         v;  [[ -n "$v" ]] && NTFY_TOPIC="$v"
read -rp "  ntfy server (default https://ntfy.sh) [${NTFY_SERVER:-}]: " v; [[ -n "$v" ]] && NTFY_SERVER="$v"
read -rp "  Slack webhook URL            [${SLACK_WEBHOOK_URL:-}]: "  v;  [[ -n "$v" ]] && SLACK_WEBHOOK_URL="$v"
read -rp "  Gotify URL                   [${GOTIFY_URL:-}]: "         v;  [[ -n "$v" ]] && GOTIFY_URL="$v"
read -rp "  Gotify app token             [${GOTIFY_TOKEN:-}]: "       v;  [[ -n "$v" ]] && GOTIFY_TOKEN="$v"
read -rp "  Generic webhook (JSON POST)  [${GENERIC_WEBHOOK_URL:-}]: " v; [[ -n "$v" ]] && GENERIC_WEBHOOK_URL="$v"

umask 077
cat > "$CONF" <<CFG
# /etc/ddos-protect/notify.env  (mode 600)
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
GOTIFY_URL="${GOTIFY_URL:-}"
GOTIFY_TOKEN="${GOTIFY_TOKEN:-}"
GENERIC_WEBHOOK_URL="${GENERIC_WEBHOOK_URL:-}"
CFG
chmod 600 "$CONF"
ok "Wrote $CONF (mode 600)"

# Install CLI shim.
cat > "$BIN" <<HELPER
#!/usr/bin/env bash
# ddos-notify — send an alert through every configured channel.
# Usage: ddos-notify "Title" "Message" [info|warn|critical]
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/notify.sh"
send_notification "\${1:-DDoS-Protect}" "\${2:-}" "\${3:-info}"
HELPER
chmod +x "$BIN"

# fail2ban action: notify on every ban.
mkdir -p /etc/fail2ban/action.d
cat > /etc/fail2ban/action.d/ddos-notify.conf <<F2B
[Definition]
actionstart =
actionstop  =
actioncheck =
actionban   = /usr/local/bin/ddos-notify "fail2ban ban" "<ip> banned in <name> jail (\$(hostname))" warn
actionunban = /usr/local/bin/ddos-notify "fail2ban unban" "<ip> released from <name>" info
F2B

# Smoke test.
if yesno "Send a test notification now?" yes; then
    if "$BIN" "DDoS-Protect test" "Hello from $(hostname). All configured channels just got pinged." info; then
        ok "Test fired — check your channels"
    else
        log warn "Test send returned non-zero; check $CONF and channel credentials"
    fi
fi

ok "Notifications wired in. Use 'ddos-notify' from anywhere."
note "fail2ban action 'ddos-notify' is available — append to jails' action= line to alert on every ban."
