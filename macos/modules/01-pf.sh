#!/usr/bin/env bash
# macOS 01-pf.sh — install the ddos-protect pf anchor.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"

mkdir -p /etc/ddos-protect /etc/pf.anchors
[[ -f /etc/ddos-protect/whitelist.txt ]] || cat > /etc/ddos-protect/whitelist.txt <<'WL'
# One IP or CIDR per line. Whitelisted hosts bypass all pf rate-limits.
WL

cp "${DDOS_SCRIPT_DIR}/macos/configs/pf/ddos-protect.conf" /etc/pf.anchors/ddos-protect

# Hook the anchor into /etc/pf.conf exactly once.
if ! grep -q 'ddos-protect' /etc/pf.conf; then
    cp /etc/pf.conf /etc/pf.conf.ddos-backup
    cat >> /etc/pf.conf <<'HOOK'

# Advanced DDoS Protections Setup
anchor "ddos-protect"
load anchor "ddos-protect" from "/etc/pf.anchors/ddos-protect"
HOOK
fi

# Validate then load.
pfctl -nf /etc/pf.conf || { fail "pf syntax check failed; rolling back"; mv /etc/pf.conf.ddos-backup /etc/pf.conf; exit 1; }
pfctl -ef /etc/pf.conf 2>&1 | sed 's/^/    /' || true
ok "pf anchor 'ddos-protect' loaded"
