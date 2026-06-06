#!/usr/bin/env bash
# 11-unsafe-services.sh — disable historically-exploited services if installed
# but not actively wanted. Every disablement leaves a marker in $STATE_DIR so
# uninstall.sh can re-enable.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"
source "${DDOS_SCRIPT_DIR}/lib/detect.sh"

STATE_DIR="${DDOS_SCRIPT_DIR}/linux/state"
mkdir -p "$STATE_DIR"

# Candidates: name + reason. We don't touch anything not present.
declare -A CANDIDATES=(
    [telnet.socket]="cleartext shell (replaced by SSH)"
    [rsh.socket]="cleartext rsh"
    [rlogin.socket]="cleartext rlogin"
    [rexec.socket]="cleartext rexec"
    [tftp.socket]="trivial-FTP — no auth, common amplifier"
    [avahi-daemon]="mDNS — leaks host info on LAN"
    [cups]="print server — exploited via IPP if exposed"
    [cups-browsed]="auto-discover printers — DDoS amp vector"
    [rpcbind]="portmapper — DDoS amp vector if exposed"
    [nfs-server]="NFS — only enable on file-server hosts"
    [snmpd]="SNMP — amp vector if community public"
    [vsftpd]="legacy FTP if not in use"
)

step "Disabling unused, exploited-by-default services"
for svc in "${!CANDIDATES[@]}"; do
    reason="${CANDIDATES[$svc]}"
    base="${svc%.socket}"
    if systemctl list-unit-files "$svc" 2>/dev/null | grep -q "$svc"; then
        # Skip if it's actively in use (recent connections, or running)
        if systemctl is-active --quiet "$svc"; then
            if yesno "  Disable $svc? ($reason)"; then
                systemctl is-enabled --quiet "$svc" && \
                    touch "$STATE_DIR/unsafe-svc-${base}.was-enabled"
                systemctl disable --now "$svc" >/dev/null 2>&1 || true
                ok "  $svc disabled"
            else
                note "  kept $svc"
            fi
        else
            # not running — quietly mask so it can't come back via socket activation
            systemctl is-enabled --quiet "$svc" 2>/dev/null && \
                touch "$STATE_DIR/unsafe-svc-${base}.was-enabled"
            systemctl disable "$svc" >/dev/null 2>&1 || true
        fi
    fi
done

ok "Unsafe-services pass complete"
