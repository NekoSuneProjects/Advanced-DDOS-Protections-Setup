#!/usr/bin/env bash
# uninstall.sh — reverses every change install.sh made by reading state.json.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ui.sh"
source "${SCRIPT_DIR}/lib/detect.sh"

OS="$(detect_os)"
case "$OS" in
    linux) STATE_DIR="${SCRIPT_DIR}/linux/state" ;;
    macos) STATE_DIR="${SCRIPT_DIR}/macos/state" ;;
    *) echo "Unsupported OS" >&2; exit 1 ;;
esac
STATE_FILE="${STATE_DIR}/state.json"

require_root
banner

if [[ ! -s "$STATE_FILE" ]]; then
    log warn "No state.json found at ${STATE_FILE}."
    log warn "Best-effort cleanup: removing DDOS_PROTECT firewall chains and"
    log warn "common config drop-ins. Manual review may be needed."
    if ! yesno "Proceed with best-effort uninstall?" no; then
        exit 1
    fi
fi

log info "Reverting installed modules in reverse order..."

# ---------- Firewall (Linux) ----------
revert_linux_firewall() {
    step "Removing iptables/nftables DDOS_PROTECT rules"
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -j DDOS_PROTECT 2>/dev/null || true
        iptables -F DDOS_PROTECT 2>/dev/null || true
        iptables -X DDOS_PROTECT 2>/dev/null || true
        ok "iptables chain removed"
    fi
    if command -v nft >/dev/null 2>&1; then
        nft delete table inet ddos_protect 2>/dev/null || true
        ok "nftables table removed"
    fi
    if command -v ufw >/dev/null 2>&1; then
        ufw --force delete allow 'DDoS-Protect' 2>/dev/null || true
    fi
}

# ---------- Firewall (macOS) ----------
revert_macos_firewall() {
    step "Unloading pf anchor"
    if [[ -f /etc/pf.anchors/ddos-protect ]]; then
        rm -f /etc/pf.anchors/ddos-protect
        # Remove anchor reference from /etc/pf.conf if present
        sed -i.bak '/anchor "ddos-protect"/d; /load anchor "ddos-protect"/d' /etc/pf.conf 2>/dev/null || true
        pfctl -f /etc/pf.conf 2>/dev/null || true
        ok "pf rules unloaded"
    fi
}

# ---------- sysctl ----------
revert_sysctl() {
    step "Restoring sysctl"
    rm -f /etc/sysctl.d/99-ddos-hardening.conf
    if command -v sysctl >/dev/null 2>&1; then
        sysctl --system >/dev/null 2>&1 || true
    fi
    ok "sysctl drop-in removed"
}

# ---------- fail2ban ----------
revert_fail2ban() {
    step "Removing fail2ban jail.local"
    if [[ -f /etc/fail2ban/jail.local.ddos-backup ]]; then
        mv -f /etc/fail2ban/jail.local.ddos-backup /etc/fail2ban/jail.local
    else
        rm -f /etc/fail2ban/jail.local
    fi
    rm -f /etc/fail2ban/filter.d/nginx-ddos.conf
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart fail2ban 2>/dev/null || true
    fi
    ok "fail2ban reverted"
}

# ---------- SSHd ----------
revert_sshd() {
    step "Removing SSHd drop-in"
    rm -f /etc/ssh/sshd_config.d/99-ddos-hardening.conf
    if command -v systemctl >/dev/null 2>&1; then
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    fi
    ok "sshd drop-in removed"
}

# ---------- nginx ----------
revert_nginx() {
    step "Removing nginx drop-in"
    rm -f /etc/nginx/conf.d/ddos-protection.conf
    if command -v nginx >/dev/null 2>&1; then
        nginx -t 2>/dev/null && (systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null) || true
    fi
    ok "nginx drop-in removed"
}

# ---------- Apache ----------
revert_apache() {
    step "Removing Apache drop-in"
    rm -f /etc/apache2/conf-available/ddos-hardening.conf
    rm -f /etc/httpd/conf.d/ddos-hardening.conf
    if command -v a2disconf >/dev/null 2>&1; then a2disconf ddos-hardening 2>/dev/null || true; fi
    systemctl reload apache2 2>/dev/null || systemctl reload httpd 2>/dev/null || true
    ok "Apache drop-in removed"
}

# ---------- MySQL ----------
revert_mysql() {
    step "Removing MySQL drop-in"
    rm -f /etc/mysql/conf.d/99-ddos-hardening.cnf
    rm -f /etc/my.cnf.d/99-ddos-hardening.cnf
    systemctl restart mysql 2>/dev/null || systemctl restart mariadb 2>/dev/null || true
    ok "MySQL drop-in removed"
}

# ---------- Email ----------
revert_email() {
    step "Removing email hardening drop-ins"
    rm -f /etc/postfix/main.cf.d/99-ddos-hardening.cf 2>/dev/null || true
    if [[ -f /etc/postfix/main.cf.ddos-backup ]]; then
        cp /etc/postfix/main.cf.ddos-backup /etc/postfix/main.cf
        rm -f /etc/postfix/main.cf.ddos-backup
        systemctl reload postfix 2>/dev/null || true
    fi
    rm -f /etc/dovecot/conf.d/99-ddos-hardening.conf
    systemctl reload dovecot 2>/dev/null || true
    ok "Email drop-ins removed"
}

# ---------- Unsafe-services ----------
revert_unsafe_services() {
    step "Restoring services disabled by 11-unsafe-services"
    local svc
    for svc in avahi-daemon cups rpcbind nfs-common; do
        if [[ -f "${STATE_DIR}/unsafe-svc-${svc}.was-enabled" ]]; then
            systemctl enable --now "$svc" 2>/dev/null || true
            rm -f "${STATE_DIR}/unsafe-svc-${svc}.was-enabled"
        fi
    done
    ok "Unsafe-services restored where flagged"
}

# ---------- Cloudflare / notify ----------
revert_cloudflare() {
    step "Removing Cloudflare integration"
    rm -f /etc/ddos-protect/cloudflare.env
    rm -f /usr/local/bin/ddos-cf
    ok "Cloudflare integration removed"
}

revert_notify() {
    step "Removing notification config"
    rm -f /etc/ddos-protect/notify.env
    rm -f /usr/local/bin/ddos-notify
    ok "Notification config removed"
}

# Reverse order matches install order (12 -> 1):
rm -f /usr/local/bin/ddos-protect
revert_notify
revert_cloudflare
revert_unsafe_services
# 10-audit is read-only; nothing to revert
# 09-rootkit-scan is read-only; nothing to revert
revert_email
revert_mysql
revert_apache
revert_nginx
revert_sshd
revert_fail2ban
revert_sysctl
if [[ "$OS" == "linux" ]]; then revert_linux_firewall; else revert_macos_firewall; fi

# Archive state file for forensics
if [[ -s "$STATE_FILE" ]]; then
    mv "$STATE_FILE" "${STATE_FILE}.uninstalled-$(date +%Y%m%d-%H%M%S)"
fi

# Remove dropin directory if empty
rmdir /etc/ddos-protect 2>/dev/null || true

echo
ok "Uninstall complete."
note "State archive: ${STATE_FILE}.uninstalled-*"
note "Review /etc for any leftover backups (*.ddos-backup) before deleting."
