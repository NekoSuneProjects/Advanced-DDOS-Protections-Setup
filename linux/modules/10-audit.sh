#!/usr/bin/env bash
# 10-audit.sh — read-only audit: listening sockets, SUID, cron, world-writable,
# authorized_keys for every user. Writes a report; doesn't change anything.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"
# shellcheck source=../../lib/notify.sh
source "${DDOS_SCRIPT_DIR}/lib/notify.sh"

LOGDIR=/var/log/ddos-protect
mkdir -p "$LOGDIR"
TS="$(date +%Y%m%d-%H%M%S)"
RPT="$LOGDIR/audit-$TS.txt"

{
    echo "Audit — $(hostname) — $(date)"
    echo
    echo "===== Listening sockets ====="
    if command -v ss >/dev/null 2>&1; then
        ss -tulnpH 2>/dev/null
    else
        netstat -tulnp 2>/dev/null
    fi

    echo
    echo "===== Established TCP (top 20 by foreign-IP count) ====="
    if command -v ss >/dev/null 2>&1; then
        ss -ntH state established 2>/dev/null \
            | awk '{print $5}' \
            | sed 's/:[0-9]*$//' \
            | sort | uniq -c | sort -rn | head -20
    fi

    echo
    echo "===== Cron jobs (system + per-user) ====="
    for c in /etc/cron.* /var/spool/cron/crontabs; do
        [[ -e "$c" ]] || continue
        echo "--- $c ---"
        ls -la "$c" 2>/dev/null
    done
    crontab -l 2>/dev/null || true
    grep -RH '' /etc/cron.d 2>/dev/null | head -200 || true

    echo
    echo "===== systemd timers ====="
    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-timers --no-pager 2>/dev/null | head -50
    fi

    echo
    echo "===== SUID binaries (recent first) ====="
    find / -xdev -perm -4000 -type f -printf '%T+ %p\n' 2>/dev/null | sort -r | head -50

    echo
    echo "===== World-writable files outside /tmp /var/tmp /dev /proc /sys /run ====="
    find / -xdev -type f -perm -o+w \
        -not -path '/tmp/*' -not -path '/var/tmp/*' \
        -not -path '/proc/*' -not -path '/sys/*' \
        -not -path '/dev/*' -not -path '/run/*' 2>/dev/null | head -50

    echo
    echo "===== authorized_keys per user ====="
    while IFS=: read -r user _ uid _ _ home _; do
        (( uid < 1000 && user != "root" )) && continue
        ak="$home/.ssh/authorized_keys"
        if [[ -f "$ak" ]]; then
            echo "--- $user ($ak) ---"
            awk '{print NR": "$1, $2, $NF}' "$ak"
        fi
    done < /etc/passwd

    echo
    echo "===== Recent auth failures (last 50) ====="
    journalctl _SYSTEMD_UNIT=ssh.service 2>/dev/null | grep -i 'failed' | tail -50 || true
    grep -i 'failed' /var/log/auth.log 2>/dev/null | tail -50 || true

    echo
    echo "===== Suspicious processes (no executable on disk) ====="
    ps -eo pid,user,comm,args 2>/dev/null \
        | awk 'NR>1 { exe="/proc/"$1"/exe"; cmd="readlink "exe" 2>/dev/null"; cmd|getline link; close(cmd); if (link == "" || link ~ / \(deleted\)/) print $0 }' \
        | head -30

} > "$RPT" 2>&1

ok "Audit report: $RPT"

# Highlight obvious red flags and alert.
flags=""
if grep -qE 'authorized_keys' "$RPT" && grep -cE '^---' "$RPT" >/dev/null; then
    flags+="• check authorized_keys list\n"
fi
if grep -qE '\(deleted\)' "$RPT"; then
    flags+="• processes with deleted executables\n"
fi
if grep -qE 'world-writable' "$RPT"; then
    flags+="• world-writable files found\n"
fi
if [[ -n "$flags" ]]; then
    send_notification "Audit findings on $(hostname)" "$(printf "%b\nFull report: %s" "$flags" "$RPT")" info
fi
