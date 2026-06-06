#!/usr/bin/env bash
# 03-fail2ban.sh — install fail2ban (if missing), drop in jail.local + custom filter.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"
source "${DDOS_SCRIPT_DIR}/lib/detect.sh"

if ! command -v fail2ban-server >/dev/null 2>&1; then
    log info "fail2ban not present — installing"
    case "$(detect_pkg_mgr)" in
        apt)    apt-get update -qq && apt-get install -y fail2ban >/dev/null ;;
        dnf|yum) "$(detect_pkg_mgr)" install -y fail2ban >/dev/null ;;
        pacman) pacman -S --noconfirm fail2ban >/dev/null ;;
        apk)    apk add --no-cache fail2ban >/dev/null ;;
        zypper) zypper -n install fail2ban >/dev/null ;;
        *) fail "no supported package manager — install fail2ban manually"; exit 1 ;;
    esac
else
    note "fail2ban already installed — only updating config"
fi

JAIL_SRC="${DDOS_SCRIPT_DIR}/linux/configs/fail2ban/jail.local"
FILTER_SRC="${DDOS_SCRIPT_DIR}/linux/configs/fail2ban/filter.d/nginx-ddos.conf"

# Back up any existing jail.local once.
if [[ -f /etc/fail2ban/jail.local && ! -f /etc/fail2ban/jail.local.ddos-backup ]]; then
    cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.ddos-backup
    note "Backed up existing jail.local -> jail.local.ddos-backup"
fi

install -m 0644 "$JAIL_SRC"   /etc/fail2ban/jail.local
install -m 0644 "$FILTER_SRC" /etc/fail2ban/filter.d/nginx-ddos.conf

# Disable jails whose log files don't exist on this host (less startup noise).
disable_missing_jail() {
    local jail="$1" probe="$2"
    if [[ ! -f "$probe" ]] && [[ -z "$(ls $probe 2>/dev/null)" ]]; then
        sed -i "/^\[$jail\]/,/^\[/{s/^enabled = true/enabled = false/}" /etc/fail2ban/jail.local
    fi
}
has_service nginx       || sed -i '/^\[nginx-/,/^enabled/s/^enabled = true/enabled = false/' /etc/fail2ban/jail.local
has_service apache2 && true || has_service httpd && true || sed -i '/^\[apache-/,/^enabled/s/^enabled = true/enabled = false/' /etc/fail2ban/jail.local
has_service mysqld && true || has_service mariadb && true || sed -i '/^\[mysqld-auth\]/,/^enabled/s/^enabled = true/enabled = false/' /etc/fail2ban/jail.local
has_service postfix     || sed -i '/^\[postfix\]/,/^enabled/s/^enabled = true/enabled = false/' /etc/fail2ban/jail.local
has_service dovecot     || sed -i '/^\[dovecot\]/,/^enabled/s/^enabled = true/enabled = false/' /etc/fail2ban/jail.local
has_service exim4 && true || has_service exim && true || sed -i '/^\[exim\]/,/^enabled/s/^enabled = true/enabled = false/' /etc/fail2ban/jail.local

# Validate config before reload.
if fail2ban-client -t >/dev/null 2>&1; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now fail2ban >/dev/null 2>&1 || true
        systemctl restart fail2ban
    fi
    ok "fail2ban configured and restarted"
    fail2ban-client status 2>/dev/null | sed 's/^/    /' || true
else
    fail "fail2ban config test failed — rolling back"
    [[ -f /etc/fail2ban/jail.local.ddos-backup ]] && mv -f /etc/fail2ban/jail.local.ddos-backup /etc/fail2ban/jail.local
    exit 1
fi
