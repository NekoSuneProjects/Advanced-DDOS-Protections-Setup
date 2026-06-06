#!/usr/bin/env bash
# macOS 03-fail2ban.sh — Homebrew install + SSHd jail.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"

if ! command -v brew >/dev/null 2>&1; then
    fail "Homebrew not installed. Install from https://brew.sh then re-run."
    exit 1
fi

# brew should be run as the invoking user, not root.
USER_NAME="${SUDO_USER:-$USER}"
sudo -u "$USER_NAME" brew list fail2ban >/dev/null 2>&1 || \
    sudo -u "$USER_NAME" brew install fail2ban

PREFIX="$(sudo -u "$USER_NAME" brew --prefix)"
mkdir -p "${PREFIX}/etc/fail2ban/jail.d"

cat > "${PREFIX}/etc/fail2ban/jail.d/sshd.conf" <<'CFG'
[sshd]
enabled  = true
filter   = sshd
port     = ssh
logpath  = /var/log/system.log
maxretry = 4
findtime = 5m
bantime  = 24h
banaction = pf
CFG

sudo -u "$USER_NAME" brew services restart fail2ban || true
ok "fail2ban running via brew services (SSHd jail with pf banaction)"
