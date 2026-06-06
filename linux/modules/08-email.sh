#!/usr/bin/env bash
# 08-email.sh — Postfix / Dovecot / Exim hardening (only if installed).
# Tightens anti-relay, rate-limits, brute-force surface. fail2ban jails in 03.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"
source "${DDOS_SCRIPT_DIR}/lib/detect.sh"

did_something=0

# ---------- Postfix ----------
if command -v postconf >/dev/null 2>&1; then
    did_something=1
    [[ -f /etc/postfix/main.cf.ddos-backup ]] || cp /etc/postfix/main.cf /etc/postfix/main.cf.ddos-backup
    note "Backed up /etc/postfix/main.cf -> main.cf.ddos-backup"

    postconf -e 'smtpd_helo_required = yes'
    postconf -e 'disable_vrfy_command = yes'
    postconf -e 'smtpd_banner = $myhostname ESMTP'
    postconf -e 'smtpd_client_connection_count_limit = 30'
    postconf -e 'smtpd_client_connection_rate_limit = 60'
    postconf -e 'smtpd_client_message_rate_limit = 100'
    postconf -e 'smtpd_client_recipient_rate_limit = 200'
    postconf -e 'anvil_rate_time_unit = 60s'
    postconf -e 'smtpd_error_sleep_time = 5s'
    postconf -e 'smtpd_soft_error_limit = 3'
    postconf -e 'smtpd_hard_error_limit = 10'
    # Strong anti-relay
    postconf -e 'smtpd_relay_restrictions = permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination'
    postconf -e 'smtpd_recipient_restrictions = permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination,reject_invalid_hostname,reject_non_fqdn_hostname,reject_non_fqdn_sender,reject_non_fqdn_recipient,reject_unknown_sender_domain,reject_unknown_recipient_domain,reject_rbl_client zen.spamhaus.org,reject_rbl_client bl.spamcop.net'
    postconf -e 'smtpd_helo_restrictions = permit_mynetworks,reject_invalid_helo_hostname,reject_non_fqdn_helo_hostname'
    # TLS
    postconf -e 'smtpd_tls_security_level = may'
    postconf -e 'smtpd_tls_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1'
    postconf -e 'smtp_tls_protocols  = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1'

    systemctl reload postfix 2>/dev/null || true
    ok "Postfix hardened"
fi

# ---------- Dovecot ----------
if has_service dovecot; then
    did_something=1
    mkdir -p /etc/dovecot/conf.d
    cat > /etc/dovecot/conf.d/99-ddos-hardening.conf <<'CFG'
disable_plaintext_auth = yes
auth_failure_delay = 3 secs
login_trusted_networks =
ssl = required
ssl_min_protocol = TLSv1.2
service auth {
  client_limit = 5000
}
service imap-login {
  process_limit = 1000
  client_limit  = 10
}
service pop3-login {
  process_limit = 200
  client_limit  = 10
}
CFG
    systemctl reload dovecot 2>/dev/null || true
    ok "Dovecot hardened"
fi

# ---------- Exim ----------
if command -v exim >/dev/null 2>&1 || command -v exim4 >/dev/null 2>&1; then
    did_something=1
    note "Exim detected — recommended hardening:"
    note "  - smtp_accept_max_per_host = 20"
    note "  - smtp_accept_queue_per_connection = 20"
    note "  - rcpt_4xx_limit defenses (see official docs)"
    note "Exim config is site-specific; not auto-patched."
fi

(( did_something )) || note "No mail services detected — skipping"
