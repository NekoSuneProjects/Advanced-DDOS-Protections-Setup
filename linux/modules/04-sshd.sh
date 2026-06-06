#!/usr/bin/env bash
# 04-sshd.sh — SSHd hardening drop-in.
# Refuses to disable password auth if the current admin has no authorized_keys.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"
source "${DDOS_SCRIPT_DIR}/lib/detect.sh"

if ! has_service sshd && ! has_service ssh; then
    note "sshd not installed — skipping"
    exit 0
fi

mkdir -p /etc/ssh/sshd_config.d
DROPIN=/etc/ssh/sshd_config.d/99-ddos-hardening.conf

# Decide whether disabling password auth is safe.
LOGIN_USER="${SUDO_USER:-$USER}"
KEY_FILE="/home/${LOGIN_USER}/.ssh/authorized_keys"
[[ "$LOGIN_USER" == "root" ]] && KEY_FILE=/root/.ssh/authorized_keys

DISABLE_PW="no"
if [[ -s "$KEY_FILE" ]]; then
    DISABLE_PW="yes"
    note "Found authorized_keys for ${LOGIN_USER} — password auth will be disabled"
else
    log warn "No authorized_keys for ${LOGIN_USER}. Leaving PasswordAuthentication enabled"
    log warn "to avoid locking you out. Add a key, then re-run module 04 to disable."
fi

cat >"$DROPIN" <<CFG
# Installed by Advanced DDoS Protections Setup. Reverse via uninstall.sh.
Protocol 2
PermitRootLogin no
$( [[ "$DISABLE_PW" == "yes" ]] && echo 'PasswordAuthentication no' || echo '#PasswordAuthentication no  # left enabled (no key found)' )
PermitEmptyPasswords no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
MaxAuthTries 3
LoginGraceTime 30
MaxStartups 10:30:60
ClientAliveInterval 300
ClientAliveCountMax 2
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
UseDNS no
TCPKeepAlive yes
LogLevel VERBOSE
Banner none

# Modern crypto only
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
CFG

# Validate before reload.
if ! sshd -t -f /etc/ssh/sshd_config 2>/tmp/sshd-test.log; then
    fail "sshd -t failed; rolling back"
    cat /tmp/sshd-test.log
    rm -f "$DROPIN"
    exit 1
fi

systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
ok "SSHd hardened (drop-in: ${DROPIN})"
