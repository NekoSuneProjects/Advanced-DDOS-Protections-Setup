#!/usr/bin/env bash
# 05-nginx.sh — drop in /etc/nginx/conf.d/ddos-protection.conf if nginx is present.
# Never installs nginx; only hardens an existing install.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"
source "${DDOS_SCRIPT_DIR}/lib/detect.sh"

if ! command -v nginx >/dev/null 2>&1; then
    note "nginx not installed — skipping (we don't install web servers)"
    exit 0
fi

SRC="${DDOS_SCRIPT_DIR}/linux/configs/nginx/ddos-protection.conf"
DST="/etc/nginx/conf.d/ddos-protection.conf"

[[ -d /etc/nginx/conf.d ]] || mkdir -p /etc/nginx/conf.d
install -m 0644 "$SRC" "$DST"

# Validate. If nginx -t fails, remove drop-in and abort.
if ! nginx -t 2>/tmp/nginx-test.log; then
    fail "nginx -t failed after dropping in protection config; rolling back"
    cat /tmp/nginx-test.log
    rm -f "$DST"
    exit 1
fi

systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
ok "nginx drop-in installed: ${DST}"
note "Add these lines to each protected server{} block:"
note '    include /etc/nginx/conf.d/ddos-protection.conf;'
note '    if ($bad_method) { return 405; }'
note '    if ($bad_ua)     { return 444; }'
note '    if ($bad_ref)    { return 444; }'
note '    limit_req  zone=req_general burst=20 nodelay;'
note '    limit_conn conn_perip      20;'
