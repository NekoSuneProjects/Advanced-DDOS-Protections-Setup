#!/usr/bin/env bash
# 14-monitor.sh — install a tiny systemd service+timer that watches
# CPU, memory, network bandwidth, and TCP connection count, and fires
# a notification when any threshold is breached.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"

WATCHER=/usr/local/bin/ddos-watcher
ENV_FILE=/etc/ddos-protect/monitor.env
mkdir -p /etc/ddos-protect

# Defaults — easy to tune later.
[[ -f "$ENV_FILE" ]] || cat > "$ENV_FILE" <<'CFG'
# /etc/ddos-protect/monitor.env
# Thresholds for the ddos-watcher. Edit and restart the timer to apply.
CPU_PCT_THRESHOLD=85           # 1-min loadavg-equivalent percent
MEM_PCT_THRESHOLD=90
RX_MBPS_THRESHOLD=400          # incoming network bandwidth
TX_MBPS_THRESHOLD=400          # outgoing
CONN_COUNT_THRESHOLD=3000      # established+syn-recv TCP connections
ALERT_COOLDOWN_SECONDS=600     # don't spam the channels
CFG

# Watcher script.
cat > "$WATCHER" <<'WATCH'
#!/usr/bin/env bash
# ddos-watcher — single-shot snapshot. Called by a systemd timer every minute.
set -euo pipefail
ENV_FILE=/etc/ddos-protect/monitor.env
STATE=/var/lib/ddos-protect
mkdir -p "$STATE"
# shellcheck source=/dev/null
[[ -r "$ENV_FILE" ]] && . "$ENV_FILE"
# shellcheck source=/dev/null
[[ -r /etc/ddos-protect/notify.env ]] && { set -a; . /etc/ddos-protect/notify.env; set +a; }

# Source notify lib if the install dir is reachable.
DDOS_DIR="${DDOS_INSTALL_DIR:-/opt/ddos-protect}"
[[ -r "$DDOS_DIR/lib/notify.sh" ]] && source "$DDOS_DIR/lib/notify.sh"
type send_notification >/dev/null 2>&1 || send_notification() { logger -t ddos-watcher "$1: $2"; }

cooldown() {
    local key="$1" now
    now="$(date +%s)"
    local mark="$STATE/cooldown-$key"
    if [[ -f "$mark" ]]; then
        local last; last="$(cat "$mark")"
        (( now - last < ${ALERT_COOLDOWN_SECONDS:-600} )) && return 1
    fi
    echo "$now" > "$mark"
    return 0
}

# CPU%: average over 1s using /proc/stat delta.
read -r _ u1 n1 s1 i1 io1 _ < /proc/stat
sleep 1
read -r _ u2 n2 s2 i2 io2 _ < /proc/stat
total=$(( (u2+n2+s2+i2+io2) - (u1+n1+s1+i1+io1) ))
idle=$((  (i2+io2) - (i1+io1) ))
cpu_pct=$(( total > 0 ? 100 * (total-idle) / total : 0 ))

# Mem%
read -r _ memtotal _ < <(grep -m1 MemTotal /proc/meminfo)
read -r _ memavail _ < <(grep -m1 MemAvailable /proc/meminfo)
mem_pct=$(( memtotal > 0 ? 100 * (memtotal-memavail) / memtotal : 0 ))

# Bandwidth on the default route iface.
iface="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
rx_mbps=0; tx_mbps=0
if [[ -n "$iface" && -r /sys/class/net/$iface/statistics/rx_bytes ]]; then
    rx1=$(< /sys/class/net/$iface/statistics/rx_bytes)
    tx1=$(< /sys/class/net/$iface/statistics/tx_bytes)
    sleep 1
    rx2=$(< /sys/class/net/$iface/statistics/rx_bytes)
    tx2=$(< /sys/class/net/$iface/statistics/tx_bytes)
    rx_mbps=$(( (rx2-rx1)*8 / 1000000 ))
    tx_mbps=$(( (tx2-tx1)*8 / 1000000 ))
fi

# TCP conn count
conn_count=0
if command -v ss >/dev/null 2>&1; then
    conn_count=$(ss -tnH state established state syn-recv 2>/dev/null | wc -l)
fi

# Persist current sample for `ddos-status`.
cat > "$STATE/last-sample.txt" <<S
ts=$(date -u +%FT%TZ)
iface=$iface
cpu_pct=$cpu_pct
mem_pct=$mem_pct
rx_mbps=$rx_mbps
tx_mbps=$tx_mbps
conn_count=$conn_count
S

# Trigger alerts.
trip() {
    local key="$1" sev="$2" title="$3" msg="$4"
    cooldown "$key" || return 0
    send_notification "$title" "$msg" "$sev"
}

(( cpu_pct >= ${CPU_PCT_THRESHOLD:-85} )) && \
    trip cpu warn "High CPU on $(hostname)" \
        "CPU at ${cpu_pct}% (threshold ${CPU_PCT_THRESHOLD:-85}%). Top:
$(ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -6)"

(( mem_pct >= ${MEM_PCT_THRESHOLD:-90} )) && \
    trip mem warn "High memory on $(hostname)" \
        "Memory at ${mem_pct}% (threshold ${MEM_PCT_THRESHOLD:-90}%). Top:
$(ps -eo pid,user,%cpu,%mem,comm --sort=-%mem | head -6)"

(( rx_mbps >= ${RX_MBPS_THRESHOLD:-400} )) && \
    trip rx critical "Inbound flood on $(hostname)" \
        "RX ${rx_mbps} Mbps on ${iface} (threshold ${RX_MBPS_THRESHOLD:-400}). Possible DDoS."

(( tx_mbps >= ${TX_MBPS_THRESHOLD:-400} )) && \
    trip tx warn "High outbound on $(hostname)" \
        "TX ${tx_mbps} Mbps on ${iface}. Check for compromised process."

(( conn_count >= ${CONN_COUNT_THRESHOLD:-3000} )) && \
    trip conn critical "TCP conn flood on $(hostname)" \
        "${conn_count} established+syn-recv connections (threshold ${CONN_COUNT_THRESHOLD:-3000})."

exit 0
WATCH
chmod +x "$WATCHER"

# Status CLI.
cat > /usr/local/bin/ddos-status <<'STAT'
#!/usr/bin/env bash
S=/var/lib/ddos-protect/last-sample.txt
[[ -r "$S" ]] || { echo "no sample yet — wait one minute for the timer"; exit 1; }
. "$S"
printf 'Host:    %s\n' "$(hostname)"
printf 'Sample:  %s\n' "$ts"
printf 'Iface:   %s\n' "$iface"
printf 'CPU:     %s%%\n' "$cpu_pct"
printf 'Memory:  %s%%\n' "$mem_pct"
printf 'RX:      %s Mbps\n' "$rx_mbps"
printf 'TX:      %s Mbps\n' "$tx_mbps"
printf 'TCP:     %s established+syn-recv\n' "$conn_count"
STAT
chmod +x /usr/local/bin/ddos-status

# systemd unit + timer.
cat > /etc/systemd/system/ddos-watcher.service <<UNIT
[Unit]
Description=Advanced DDoS Protections watcher
After=network.target

[Service]
Type=oneshot
Environment=DDOS_INSTALL_DIR=${DDOS_SCRIPT_DIR}
ExecStart=${WATCHER}
UNIT

cat > /etc/systemd/system/ddos-watcher.timer <<TIMER
[Unit]
Description=Run DDoS watcher every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
Unit=ddos-watcher.service

[Install]
WantedBy=timers.target
TIMER

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl enable --now ddos-watcher.timer >/dev/null 2>&1
    ok "Watcher timer active (every 60s)"
else
    log warn "systemd not detected — add a cron entry to run $WATCHER every minute"
fi

note "Tuning:  edit $ENV_FILE and 'systemctl restart ddos-watcher.timer'"
note "Status:  run 'ddos-status' anytime"
