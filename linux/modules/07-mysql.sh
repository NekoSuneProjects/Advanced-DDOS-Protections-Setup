#!/usr/bin/env bash
# 07-mysql.sh — MySQL / MariaDB hardening drop-in (only if installed).
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"
source "${DDOS_SCRIPT_DIR}/lib/detect.sh"

if ! has_service mysqld && ! has_service mariadb && ! has_service mysql; then
    note "MySQL/MariaDB not installed — skipping"
    exit 0
fi

# Both Debian/Ubuntu (/etc/mysql/conf.d/) and RHEL (/etc/my.cnf.d/) styles.
DST=""
[[ -d /etc/mysql/conf.d ]] && DST=/etc/mysql/conf.d/99-ddos-hardening.cnf
[[ -d /etc/my.cnf.d ]]     && DST=/etc/my.cnf.d/99-ddos-hardening.cnf
[[ -z "$DST" ]] && { mkdir -p /etc/mysql/conf.d; DST=/etc/mysql/conf.d/99-ddos-hardening.cnf; }

cat > "$DST" <<'CFG'
[mysqld]
# Listen on localhost only by default. If you serve remote clients, comment
# this out and rely on the firewall + per-host GRANTS instead.
bind-address            = 127.0.0.1

skip-show-database
skip-name-resolve
local-infile            = 0
secure-file-priv        = /var/lib/mysql-files

# Connection limits — keep brute-forcers from chewing thread pool.
max_connections         = 200
max_user_connections    = 30
max_connect_errors      = 100
connect_timeout         = 5
wait_timeout            = 180
interactive_timeout     = 180

# Log auth failures so fail2ban's mysqld-auth jail has something to read.
log_warnings            = 2
log_error               = /var/log/mysql/error.log
CFG

# Try to restart; if it fails roll back.
RESTART=""
if systemctl list-units --type=service 2>/dev/null | grep -q mariadb; then RESTART="systemctl restart mariadb"
elif systemctl list-units --type=service 2>/dev/null | grep -q 'mysql\.service\|mysqld'; then RESTART="systemctl restart mysql || systemctl restart mysqld"
fi

if [[ -n "$RESTART" ]]; then
    if eval "$RESTART" 2>/tmp/mysql-restart.log; then
        ok "MySQL/MariaDB hardened (drop-in: $DST)"
    else
        fail "MySQL restart failed; restoring"
        cat /tmp/mysql-restart.log
        rm -f "$DST"
        eval "$RESTART" || true
        exit 1
    fi
else
    ok "Config written ($DST). Restart MySQL/MariaDB manually to apply."
fi
