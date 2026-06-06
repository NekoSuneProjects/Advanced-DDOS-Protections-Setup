#!/usr/bin/env bash
# 02-sysctl.sh — install /etc/sysctl.d/99-ddos-hardening.conf and apply.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"

SRC="${DDOS_SCRIPT_DIR}/linux/configs/sysctl/99-ddos-hardening.conf"
DST="/etc/sysctl.d/99-ddos-hardening.conf"

[[ -r "$SRC" ]] || { fail "missing config: $SRC"; exit 1; }
install -m 0644 "$SRC" "$DST"

if command -v sysctl >/dev/null 2>&1; then
    if sysctl --system >/dev/null 2>&1; then
        ok "Kernel/TCP hardening applied"
    else
        log warn "sysctl --system reported errors (often noisy on containers — non-fatal)"
    fi
else
    log warn "sysctl binary not found — values written but not loaded"
fi

note "Drop-in: ${DST}"
