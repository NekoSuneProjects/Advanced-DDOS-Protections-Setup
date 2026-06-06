#!/usr/bin/env bash
# macOS 04-sshd.sh — SSHd hardening via /etc/ssh/sshd_config.d.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"

# Recent macOS supports sshd_config.d Include. Older systems need direct edit.
if [[ ! -d /etc/ssh/sshd_config.d ]]; then
    mkdir -p /etc/ssh/sshd_config.d
    grep -q "Include /etc/ssh/sshd_config.d/" /etc/ssh/sshd_config || \
        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
fi

DROPIN=/etc/ssh/sshd_config.d/99-ddos-hardening.conf
cat >"$DROPIN" <<CFG
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
UseDNS no
CFG

if launchctl list | grep -q com.openssh.sshd; then
    launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
    launchctl load   /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
fi
ok "SSHd hardened (drop-in: $DROPIN)"
