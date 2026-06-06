#!/usr/bin/env bash
# macOS 02-sysctl.sh — runtime TCP stack hardening. macOS doesn't read /etc/sysctl.d
# so we apply at runtime and persist via /Library/LaunchDaemons.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"

apply_one() { sysctl -w "$1" >/dev/null 2>&1 && note "  $1"; }

apply_one net.inet.icmp.icmplim=50
apply_one net.inet.ip.redirect=0
apply_one net.inet.tcp.blackhole=2
apply_one net.inet.udp.blackhole=1
apply_one net.inet.icmp.bmcastecho=0
apply_one net.inet.icmp.maskrepl=0
apply_one net.inet.icmp.drop_redirect=1
apply_one net.inet.tcp.drop_synfin=1
apply_one net.inet.ip.sourceroute=0
apply_one net.inet.ip.accept_sourceroute=0

# Persist with a LaunchDaemon so reboots keep the values.
cat > /Library/LaunchDaemons/com.ddosprotect.sysctl.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.ddosprotect.sysctl</string>
  <key>RunAtLoad</key><true/>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string><string>-c</string>
    <string>sysctl -w net.inet.icmp.icmplim=50 net.inet.ip.redirect=0 net.inet.tcp.blackhole=2 net.inet.udp.blackhole=1 net.inet.icmp.bmcastecho=0 net.inet.icmp.maskrepl=0 net.inet.icmp.drop_redirect=1 net.inet.tcp.drop_synfin=1 net.inet.ip.sourceroute=0 net.inet.ip.accept_sourceroute=0</string>
  </array>
</dict>
</plist>
PLIST

launchctl unload /Library/LaunchDaemons/com.ddosprotect.sysctl.plist 2>/dev/null || true
launchctl load -w /Library/LaunchDaemons/com.ddosprotect.sysctl.plist
ok "sysctl hardening persisted via LaunchDaemon"
