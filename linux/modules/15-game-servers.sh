#!/usr/bin/env bash
# 15-game-servers.sh — flood protection for game / voice servers.
# Detects Minecraft Java (25565/tcp), Minecraft Bedrock (19132/udp),
# FiveM (30120/udp), TeamSpeak3 (9987/udp + 10011/tcp + 30033/tcp),
# Mumble (64738/udp+tcp), Source-engine (27015/udp+tcp), Valheim (2456/udp).
# Adds tight per-source rate-limits in the DDOS_PROTECT chain.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"
source "${DDOS_SCRIPT_DIR}/lib/detect.sh"

CHAIN="DDOS_PROTECT"
command -v iptables >/dev/null 2>&1 || { fail "iptables not installed — run module 01 first"; exit 1; }
iptables -L "$CHAIN" -n >/dev/null 2>&1 || { fail "Chain $CHAIN missing — run module 01 first"; exit 1; }

listening_udp="$(detect_listening_udp_ports)"
listening_tcp=""
if command -v ss >/dev/null 2>&1; then
    listening_tcp="$(ss -ltnH 2>/dev/null | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | tr '\n' ' ')"
fi

is_udp_listening() { grep -qw "$1" <<<"$listening_udp"; }
is_tcp_listening() { grep -qw "$1" <<<"$listening_tcp"; }

# Helper: per-source-IP packets/sec cap on a UDP port.
udp_cap() {
    local port="$1" pps="$2" burst="$3" label="$4"
    iptables -A "$CHAIN" -p udp --dport "$port" \
        -m hashlimit --hashlimit-name "g-${label}-${port}" \
        --hashlimit-above "${pps}/sec" --hashlimit-burst "$burst" \
        --hashlimit-mode srcip -j DROP
}

# Helper: per-source-IP new-conn cap on a TCP port.
tcp_cap() {
    local port="$1" pps="$2" burst="$3" label="$4" concurrent="${5:-20}"
    iptables -A "$CHAIN" -p tcp --syn --dport "$port" \
        -m hashlimit --hashlimit-name "g-${label}-${port}" \
        --hashlimit-above "${pps}/sec" --hashlimit-burst "$burst" \
        --hashlimit-mode srcip -j DROP
    iptables -m connlimit -h >/dev/null 2>&1 && \
        iptables -A "$CHAIN" -p tcp --syn --dport "$port" \
            -m connlimit --connlimit-above "$concurrent" -j REJECT --reject-with tcp-reset
}

added=0

# Minecraft Java — 25565/tcp
if is_tcp_listening 25565; then
    tcp_cap 25565 5 10 minecraft-java 10; added=1; ok "Minecraft Java: rate-limit + connlimit applied"
fi
# Minecraft Bedrock — 19132/udp (RakNet)
if is_udp_listening 19132; then
    udp_cap 19132 60 120 minecraft-bedrock; added=1; ok "Minecraft Bedrock: UDP rate-limit applied"
fi
# FiveM (GTA-V) — 30120/udp
if is_udp_listening 30120; then
    udp_cap 30120 120 240 fivem; added=1; ok "FiveM: UDP rate-limit applied"
fi
# TS3 voice 9987/udp + query 10011/tcp + file 30033/tcp
if is_udp_listening 9987; then
    udp_cap 9987 80 160 ts3-voice; added=1
fi
if is_tcp_listening 10011; then
    tcp_cap 10011 2 5  ts3-query 5; added=1
fi
if is_tcp_listening 30033; then
    tcp_cap 30033 5 10 ts3-file 10; added=1
fi
[[ added -eq 1 ]] && ok "TeamSpeak3 ports protected"
# Mumble 64738
if is_udp_listening 64738 || is_tcp_listening 64738; then
    udp_cap 64738 80 160 mumble; added=1; ok "Mumble: rate-limit applied"
fi
# Source engine 27015 (CS:GO/TF2)
if is_udp_listening 27015; then
    udp_cap 27015 50 100 source-engine; added=1; ok "Source engine: rate-limit applied"
fi
# Valheim 2456-2458/udp
for p in 2456 2457 2458; do
    is_udp_listening "$p" && { udp_cap "$p" 40 80 valheim; added=1; }
done
# RCON 2302/udp (DayZ, Arma)
if is_udp_listening 2302; then
    udp_cap 2302 40 80 rcon-2302; added=1
fi

if (( added == 0 )); then
    note "No game-server ports detected. Add tighter rules manually with iptables -A DDOS_PROTECT ..."
else
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    ok "Game-server protections committed to chain $CHAIN"
fi
