#!/usr/bin/env bash
# 01-firewall.sh — iptables-based edge firewall + rate limit + amp-port blackhole.
# All rules live in a dedicated chain DDOS_PROTECT so uninstall is trivial.
# Reads whitelist from /etc/ddos-protect/whitelist.txt (one IP or CIDR per line).
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"
source "${DDOS_SCRIPT_DIR}/lib/detect.sh"

CHAIN="DDOS_PROTECT"
WHITELIST="/etc/ddos-protect/whitelist.txt"
mkdir -p /etc/ddos-protect

# Seed an empty whitelist file with examples on first run.
if [[ ! -f "$WHITELIST" ]]; then
    cat > "$WHITELIST" <<'WL'
# /etc/ddos-protect/whitelist.txt
# One IP or CIDR per line. These hosts bypass every rate-limit and
# amp-port blackhole rule installed by this toolkit.
# Examples (uncomment to use):
# 10.0.0.0/8
# 192.168.0.0/16
# 1.2.3.4
WL
    note "Created whitelist template at ${WHITELIST}"
fi

# Choose backend.
BACKEND="$(detect_firewall_backend)"
case "$BACKEND" in
    nftables) note "Using nftables backend" ;;
    iptables) note "Using iptables backend" ;;
    ufw)      note "ufw present but we install raw iptables rules under it" ;;
    none)
        log warn "No firewall backend found. Installing iptables."
        case "$(detect_pkg_mgr)" in
            apt)    apt-get update -qq && apt-get install -y iptables iptables-persistent >/dev/null ;;
            dnf|yum) "$(detect_pkg_mgr)" install -y iptables-services >/dev/null ;;
            pacman) pacman -S --noconfirm iptables >/dev/null ;;
            apk)    apk add --no-cache iptables >/dev/null ;;
            zypper) zypper -n install iptables >/dev/null ;;
            *) fail "No supported package manager; install iptables manually."; exit 1 ;;
        esac
        BACKEND="iptables"
        ;;
esac

# ---------- Build rules (iptables form) ----------
build_iptables_rules() {
    iptables -N "$CHAIN" 2>/dev/null || iptables -F "$CHAIN"

    # 1. Whitelist short-circuit (ACCEPT before any limit).
    local ip
    while IFS= read -r ip; do
        ip="${ip%%#*}"; ip="${ip// /}"
        [[ -z "$ip" ]] && continue
        iptables -A "$CHAIN" -s "$ip" -j ACCEPT
    done < "$WHITELIST"

    # 2. Allow established/related and loopback unconditionally.
    iptables -A "$CHAIN" -i lo -j ACCEPT
    iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # 3. Drop invalid packets.
    iptables -A "$CHAIN" -m conntrack --ctstate INVALID -j DROP

    # 4. Drop NEW non-SYN (common scan signature).
    iptables -A "$CHAIN" -p tcp ! --syn -m conntrack --ctstate NEW -j DROP

    # 5. Drop XMAS / NULL scans.
    iptables -A "$CHAIN" -p tcp --tcp-flags ALL ALL -j DROP
    iptables -A "$CHAIN" -p tcp --tcp-flags ALL NONE -j DROP
    iptables -A "$CHAIN" -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
    iptables -A "$CHAIN" -p tcp --tcp-flags SYN,RST SYN,RST -j DROP

    # 6. Fragment drop.
    iptables -A "$CHAIN" -f -j DROP

    # 7. ICMP rate-limit (allow ping but capped).
    iptables -A "$CHAIN" -p icmp --icmp-type echo-request \
        -m hashlimit --hashlimit-name icmp-ping --hashlimit-above 4/sec --hashlimit-burst 8 \
        --hashlimit-mode srcip -j DROP
    iptables -A "$CHAIN" -p icmp --icmp-type address-mask-request -j DROP
    iptables -A "$CHAIN" -p icmp --icmp-type timestamp-request -j DROP

    # 8. SYN flood rate-limit per source IP.
    iptables -A "$CHAIN" -p tcp --syn \
        -m hashlimit --hashlimit-name syn-flood --hashlimit-above 25/sec --hashlimit-burst 50 \
        --hashlimit-mode srcip -j DROP

    # 9. Concurrent connection cap per source IP (web ports).
    if iptables -m connlimit -h >/dev/null 2>&1; then
        iptables -A "$CHAIN" -p tcp --syn --dport 80  -m connlimit --connlimit-above 60 -j REJECT --reject-with tcp-reset
        iptables -A "$CHAIN" -p tcp --syn --dport 443 -m connlimit --connlimit-above 60 -j REJECT --reject-with tcp-reset
    fi

    # 10. Amp-port blackhole: drop inbound UDP from reflected source ports unless
    #     we're actually running that service locally.
    local listening_udp; listening_udp="$(detect_listening_udp_ports)"
    local amp_port
    for amp_port in 19 53 123 389 1900 11211 17 27015 7777 5683 27960; do
        if ! grep -qw "$amp_port" <<<"$listening_udp"; then
            iptables -A "$CHAIN" -p udp --sport "$amp_port" -j DROP
        fi
    done

    # 11. Hand off to default policy / next chain (ACCEPT — we only filter abuse).
    iptables -A "$CHAIN" -j RETURN

    # Hook the chain at the head of INPUT exactly once.
    if ! iptables -C INPUT -j "$CHAIN" 2>/dev/null; then
        iptables -I INPUT 1 -j "$CHAIN"
    fi
}

# ---------- Build rules (nftables form) ----------
build_nftables_rules() {
    cat > /etc/ddos-protect/ddos.nft <<'NFT'
table inet ddos_protect {
    set whitelist_v4 {
        type ipv4_addr; flags interval;
    }

    chain prerouting {
        type filter hook prerouting priority -310; policy accept;
        ct state invalid drop
        tcp flags & (fin|syn|rst|psh|ack|urg) == 0 drop
        tcp flags & (fin|syn) == (fin|syn) drop
        tcp flags & (syn|rst) == (syn|rst) drop
        tcp flags & (fin|psh|urg) == (fin|psh|urg) drop
        ip frag-off & 0x1fff != 0 drop
    }

    chain input {
        type filter hook input priority -300; policy accept;
        iif lo accept
        ip saddr @whitelist_v4 accept
        ct state established,related accept
        icmp type echo-request limit rate over 4/second burst 8 packets drop
        tcp flags syn limit rate over 25/second burst 50 packets drop
        tcp dport { 80, 443 } ct state new meter syn_per_ip { ip saddr limit rate over 60/second } drop
        udp sport { 19, 53, 123, 389, 1900, 11211, 17, 27015 } drop
    }
}
NFT
    nft -f /etc/ddos-protect/ddos.nft

    # Re-import whitelist into nft set.
    local ip
    while IFS= read -r ip; do
        ip="${ip%%#*}"; ip="${ip// /}"
        [[ -z "$ip" ]] && continue
        nft add element inet ddos_protect whitelist_v4 "{ $ip }" 2>/dev/null || true
    done < "$WHITELIST"
}

# ---------- Apply ----------
case "$BACKEND" in
    iptables|ufw) build_iptables_rules ;;
    nftables)     build_nftables_rules ;;
esac

# Persist across reboots.
if command -v iptables-save >/dev/null 2>&1; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save 2>/dev/null || true
fi

# Install ddos-allow helper for adding IPs to the whitelist on the fly.
cat > /usr/local/bin/ddos-allow <<'HELPER'
#!/usr/bin/env bash
# Usage: ddos-allow <ip-or-cidr>
set -euo pipefail
WL="/etc/ddos-protect/whitelist.txt"
[[ $# -eq 1 ]] || { echo "Usage: ddos-allow <ip-or-cidr>" >&2; exit 1; }
ip="$1"
grep -qxF "$ip" "$WL" || echo "$ip" >> "$WL"
if command -v nft >/dev/null 2>&1 && nft list table inet ddos_protect >/dev/null 2>&1; then
    nft add element inet ddos_protect whitelist_v4 "{ $ip }"
elif command -v iptables >/dev/null 2>&1 && iptables -L DDOS_PROTECT -n >/dev/null 2>&1; then
    iptables -I DDOS_PROTECT 1 -s "$ip" -j ACCEPT
fi
echo "[ok] $ip whitelisted"
HELPER
chmod +x /usr/local/bin/ddos-allow

ok "Firewall rules active. Helper installed: ddos-allow <ip>"
note "Edit ${WHITELIST} and re-run module 01 to refresh."
