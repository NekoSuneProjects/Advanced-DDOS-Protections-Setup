#!/usr/bin/env bash
# macOS 08-monitor.sh — LaunchDaemon-driven watcher (same thresholds as Linux).
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"

mkdir -p /etc/ddos-protect /var/lib/ddos-protect
[[ -f /etc/ddos-protect/monitor.env ]] || cat > /etc/ddos-protect/monitor.env <<'CFG'
CPU_PCT_THRESHOLD=85
MEM_PCT_THRESHOLD=90
RX_MBPS_THRESHOLD=400
TX_MBPS_THRESHOLD=400
CONN_COUNT_THRESHOLD=3000
ALERT_COOLDOWN_SECONDS=600
CFG

WATCHER=/usr/local/bin/ddos-watcher
cat > "$WATCHER" <<'WATCH'
#!/usr/bin/env bash
set -euo pipefail
ENV_FILE=/etc/ddos-protect/monitor.env
STATE=/var/lib/ddos-protect
mkdir -p "$STATE"
[[ -r "$ENV_FILE" ]] && . "$ENV_FILE"
[[ -r /etc/ddos-protect/notify.env ]] && { set -a; . /etc/ddos-protect/notify.env; set +a; }
DDOS_DIR="${DDOS_INSTALL_DIR:-/opt/ddos-protect}"
[[ -r "$DDOS_DIR/lib/notify.sh" ]] && source "$DDOS_DIR/lib/notify.sh"
type send_notification >/dev/null 2>&1 || send_notification() { logger -t ddos-watcher "$1: $2"; }

# CPU load → approximate to "percent of cores"
cores=$(sysctl -n hw.ncpu)
load=$(uptime | awk -F'load averages?: ' '{print $2}' | awk '{print $1}' | tr -d ',')
cpu_pct=$(awk -v l="$load" -v c="$cores" 'BEGIN { printf "%d", (l*100/c) }')

mem_pct=$(vm_stat | awk '
    /Pages free/    { free=$3 }
    /Pages active/  { active=$3 }
    /Pages wired/   { wired=$4 }
    /Pages inactive/{ inactive=$3 }
    END {
        gsub(/\./,"",free); gsub(/\./,"",active); gsub(/\./,"",wired); gsub(/\./,"",inactive);
        total = free+active+wired+inactive;
        if (total>0) printf "%d", (active+wired)*100/total; else print 0
    }')

iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
rx_mbps=0; tx_mbps=0
if [[ -n "$iface" ]]; then
    r1=$(netstat -ibn | awk -v i="$iface" '$1==i && $4!~/Link/ {print $7; exit}')
    t1=$(netstat -ibn | awk -v i="$iface" '$1==i && $4!~/Link/ {print $10; exit}')
    sleep 1
    r2=$(netstat -ibn | awk -v i="$iface" '$1==i && $4!~/Link/ {print $7; exit}')
    t2=$(netstat -ibn | awk -v i="$iface" '$1==i && $4!~/Link/ {print $10; exit}')
    rx_mbps=$(( (r2-r1)*8/1000000 ))
    tx_mbps=$(( (t2-t1)*8/1000000 ))
fi
conn_count=$(netstat -an -p tcp 2>/dev/null | grep -cE 'ESTABLISHED|SYN_RCVD')

cat > "$STATE/last-sample.txt" <<S
ts=$(date -u +%FT%TZ)
iface=$iface
cpu_pct=$cpu_pct
mem_pct=$mem_pct
rx_mbps=$rx_mbps
tx_mbps=$tx_mbps
conn_count=$conn_count
S

cooldown() {
    local key="$1" now mark
    now=$(date +%s); mark="$STATE/cooldown-$key"
    [[ -f "$mark" ]] && (( now - $(cat "$mark") < ${ALERT_COOLDOWN_SECONDS:-600} )) && return 1
    echo "$now" > "$mark"
}

trip() { local k="$1" sev="$2" t="$3" m="$4"; cooldown "$k" || return 0; send_notification "$t" "$m" "$sev"; }

(( cpu_pct  >= ${CPU_PCT_THRESHOLD:-85}      )) && trip cpu warn  "High CPU on $(hostname)" "CPU=${cpu_pct}%"
(( mem_pct  >= ${MEM_PCT_THRESHOLD:-90}      )) && trip mem warn  "High mem on $(hostname)" "Mem=${mem_pct}%"
(( rx_mbps  >= ${RX_MBPS_THRESHOLD:-400}     )) && trip rx critical "Inbound flood on $(hostname)" "RX=${rx_mbps} Mbps"
(( tx_mbps  >= ${TX_MBPS_THRESHOLD:-400}     )) && trip tx warn  "Outbound high on $(hostname)" "TX=${tx_mbps} Mbps"
(( conn_count >= ${CONN_COUNT_THRESHOLD:-3000} )) && trip conn critical "TCP flood on $(hostname)" "${conn_count} conns"
WATCH
chmod +x "$WATCHER"

# ddos-status helper.
cat > /usr/local/bin/ddos-status <<'STAT'
#!/usr/bin/env bash
S=/var/lib/ddos-protect/last-sample.txt
[[ -r "$S" ]] || { echo "no sample yet"; exit 1; }
. "$S"
printf '%-10s %s\n' Host: "$(hostname)"
printf '%-10s %s\n' Sample: "$ts"
printf '%-10s %s\n' CPU: "${cpu_pct}%"
printf '%-10s %s\n' Mem: "${mem_pct}%"
printf '%-10s %s\n' RX: "${rx_mbps} Mbps"
printf '%-10s %s\n' TX: "${tx_mbps} Mbps"
printf '%-10s %s\n' TCP: "$conn_count"
STAT
chmod +x /usr/local/bin/ddos-status

cat > /Library/LaunchDaemons/com.ddosprotect.watcher.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.ddosprotect.watcher</string>
  <key>ProgramArguments</key>
  <array>
    <string>${WATCHER}</string>
  </array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>DDOS_INSTALL_DIR</key><string>${DDOS_SCRIPT_DIR}</string>
  </dict>
</dict>
</plist>
PLIST

launchctl unload /Library/LaunchDaemons/com.ddosprotect.watcher.plist 2>/dev/null || true
launchctl load -w /Library/LaunchDaemons/com.ddosprotect.watcher.plist
ok "Watcher daemon active (every 60s) — run 'ddos-status' to view current sample."
