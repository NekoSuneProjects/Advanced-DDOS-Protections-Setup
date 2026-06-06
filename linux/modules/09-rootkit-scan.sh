#!/usr/bin/env bash
# 09-rootkit-scan.sh — install + run rkhunter, chkrootkit, lynis. Report findings.
# Read-only — never auto-quarantines. Suspicious findings go to /var/log/ddos-protect/
# and (optionally) the configured notification channels.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"
source "${DDOS_SCRIPT_DIR}/lib/detect.sh"
# shellcheck source=../../lib/notify.sh
source "${DDOS_SCRIPT_DIR}/lib/notify.sh"

LOGDIR=/var/log/ddos-protect
mkdir -p "$LOGDIR"
TS="$(date +%Y%m%d-%H%M%S)"

PKG="$(detect_pkg_mgr)"
install_pkg() {
    local p="$1"
    command -v "$p" >/dev/null 2>&1 && return 0
    case "$PKG" in
        apt)    apt-get install -y "$p" >/dev/null 2>&1 || return 1 ;;
        dnf|yum) "$PKG" install -y "$p" >/dev/null 2>&1 || return 1 ;;
        pacman) pacman -S --noconfirm "$p" >/dev/null 2>&1 || return 1 ;;
        apk)    apk add --no-cache "$p" >/dev/null 2>&1 || return 1 ;;
        zypper) zypper -n install "$p" >/dev/null 2>&1 || return 1 ;;
        *) return 1 ;;
    esac
}

# rkhunter
if install_pkg rkhunter; then
    rkhunter --update >/dev/null 2>&1 || true
    rkhunter --propupd --quiet >/dev/null 2>&1 || true
    note "rkhunter scanning..."
    rkhunter --check --sk --quiet --report-warnings-only \
        --logfile "$LOGDIR/rkhunter-$TS.log" || true
    ok "rkhunter log: $LOGDIR/rkhunter-$TS.log"
fi

# chkrootkit
if install_pkg chkrootkit; then
    note "chkrootkit scanning..."
    chkrootkit -q > "$LOGDIR/chkrootkit-$TS.log" 2>&1 || true
    ok "chkrootkit log: $LOGDIR/chkrootkit-$TS.log"
fi

# lynis
if install_pkg lynis; then
    note "lynis audit..."
    lynis audit system --quiet --no-colors > "$LOGDIR/lynis-$TS.log" 2>&1 || true
    ok "lynis log: $LOGDIR/lynis-$TS.log"
fi

# ClamAV — optional, heavy. Install on user opt-in only.
if yesno "Install ClamAV and scan /home + /tmp (large download)?"; then
    if install_pkg clamav && install_pkg clamav-daemon; then
        freshclam --quiet 2>/dev/null || true
        clamscan -r -i --quiet /home /tmp 2>/dev/null \
            | tee "$LOGDIR/clamav-$TS.log" || true
        ok "ClamAV log: $LOGDIR/clamav-$TS.log"
    fi
fi

# Roll the logs into a single summary + push to notifications.
summary="$LOGDIR/summary-$TS.txt"
{
    echo "Backdoor / rootkit scan — $(hostname) — $(date)"
    echo
    for f in "$LOGDIR"/*-"$TS".log; do
        [[ -f "$f" ]] || continue
        echo "===== $(basename "$f") ====="
        grep -iE 'warning|infected|rootkit|suggestion' "$f" | head -100 || true
        echo
    done
} > "$summary"

ok "Summary: $summary"

# Alert if there are any flags.
flagged="$(grep -ciE 'infected|rootkit detected|warning' "$summary" 2>/dev/null || echo 0)"
if (( flagged > 0 )); then
    send_notification "Rootkit scan: ${flagged} flag(s) on $(hostname)" \
        "$(head -c 1800 "$summary")" warn
fi
