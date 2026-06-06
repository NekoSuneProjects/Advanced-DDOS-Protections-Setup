#!/usr/bin/env bash
# macOS 05-audit.sh — read-only audit of listening ports + LaunchAgents/Daemons.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"

LOGDIR=/var/log/ddos-protect
mkdir -p "$LOGDIR"
TS="$(date +%Y%m%d-%H%M%S)"
RPT="$LOGDIR/audit-$TS.txt"

{
    echo "macOS audit — $(hostname) — $(date)"
    echo
    echo "===== Listening TCP/UDP ====="
    lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null
    echo
    lsof -nP -iUDP 2>/dev/null

    echo
    echo "===== Launch agents / daemons (all locations) ====="
    for d in /Library/LaunchDaemons /Library/LaunchAgents /System/Library/LaunchDaemons /System/Library/LaunchAgents ~/Library/LaunchAgents; do
        [[ -d "$d" ]] || continue
        echo "--- $d ---"
        ls -la "$d" 2>/dev/null
    done

    echo
    echo "===== Login items ====="
    osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || true

    echo
    echo "===== Periodic cron ====="
    for d in /etc/periodic /etc/cron.d /etc/crontab; do [[ -e "$d" ]] && ls -la "$d"; done

    echo
    echo "===== Recent ssh failures ====="
    log show --predicate 'process == "sshd"' --info --last 1h 2>/dev/null \
        | grep -i 'failed' | tail -50
} > "$RPT" 2>&1

ok "Audit report: $RPT"
