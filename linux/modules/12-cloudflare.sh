#!/usr/bin/env bash
# 12-cloudflare.sh — install the `ddos-cf` helper for Cloudflare integration.
# Free-tier compatible. Stores credentials in /etc/ddos-protect/cloudflare.env (chmod 600).
# Supports:
#   - toggle "Under Attack" security mode for a zone
#   - block / unblock an IP at zone level (used by fail2ban action)
#   - list current rules
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"

CONF=/etc/ddos-protect/cloudflare.env
BIN=/usr/local/bin/ddos-cf
mkdir -p /etc/ddos-protect

if [[ ! -f "$CONF" ]]; then
    note "First-run Cloudflare config:"
    note "  Get an API token at https://dash.cloudflare.com/profile/api-tokens"
    note "  Permissions needed: Zone:Zone:Edit, Zone:Firewall Services:Edit"
    read -rp "  Cloudflare API token (Bearer): "  CF_API_TOKEN
    read -rp "  Cloudflare Zone ID:             " CF_ZONE_ID
    umask 077
    cat > "$CONF" <<CFG
# /etc/ddos-protect/cloudflare.env
CF_API_TOKEN="${CF_API_TOKEN}"
CF_ZONE_ID="${CF_ZONE_ID}"
CFG
    chmod 600 "$CONF"
    ok "Config written: $CONF (mode 600)"
fi

cat > "$BIN" <<'HELPER'
#!/usr/bin/env bash
# ddos-cf — tiny Cloudflare ops helper.
set -euo pipefail
CONF=/etc/ddos-protect/cloudflare.env
[[ -r "$CONF" ]] || { echo "missing $CONF — re-run install.sh module 12" >&2; exit 1; }
# shellcheck source=/dev/null
. "$CONF"

api() {
    curl -sS -X "$1" -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${@:2}"
}

case "${1:-help}" in
    on)   # enable under-attack mode
        api PATCH "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/settings/security_level" \
            -d '{"value":"under_attack"}' | jq -r '.success'
        ;;
    off)  # back to medium
        api PATCH "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/settings/security_level" \
            -d '{"value":"medium"}' | jq -r '.success'
        ;;
    block)
        ip="$2"
        api POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/firewall/access_rules/rules" \
            -d "{\"mode\":\"block\",\"configuration\":{\"target\":\"ip\",\"value\":\"${ip}\"},\"notes\":\"ddos-protect: ${ip}\"}" \
            | jq -r '.result.id // .errors'
        ;;
    unblock)
        ip="$2"
        rid=$(api GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/firewall/access_rules/rules?configuration_value=${ip}" \
              | jq -r '.result[0].id // empty')
        [[ -z "$rid" ]] && { echo "no rule for $ip"; exit 0; }
        api DELETE "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/firewall/access_rules/rules/${rid}" \
            | jq -r '.success'
        ;;
    list)
        api GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/firewall/access_rules/rules?per_page=200" \
            | jq -r '.result[] | "\(.configuration.value)  \(.mode)  \(.notes // "")"'
        ;;
    *)
        cat <<USE
Usage: ddos-cf {on|off|block <ip>|unblock <ip>|list}
  on / off        toggle Cloudflare "Under Attack" mode
  block <ip>      add a zone-level block for <ip>
  unblock <ip>    remove that block
  list            list all access rules
USE
        ;;
esac
HELPER
chmod +x "$BIN"

# fail2ban action to push bans straight to Cloudflare too.
mkdir -p /etc/fail2ban/action.d
cat > /etc/fail2ban/action.d/cloudflare-ddos.conf <<'F2B'
[Definition]
actionstart =
actionstop  =
actioncheck =
actionban   = /usr/local/bin/ddos-cf block <ip>
actionunban = /usr/local/bin/ddos-cf unblock <ip>
F2B

# Need jq.
command -v jq >/dev/null 2>&1 || {
    note "Installing jq for ddos-cf"
    case "$(detect_pkg_mgr 2>/dev/null)" in
        apt) apt-get install -y jq >/dev/null ;;
        dnf|yum) ${PKG_MGR:-dnf} install -y jq >/dev/null 2>&1 ;;
        pacman) pacman -S --noconfirm jq >/dev/null ;;
        apk) apk add --no-cache jq >/dev/null ;;
        zypper) zypper -n install jq >/dev/null ;;
    esac
}

ok "Cloudflare helper installed: $BIN"
note "Quick start:  ddos-cf on     # enable under-attack mode"
note "              ddos-cf list   # show all access rules"
note "fail2ban action 'cloudflare-ddos' available — add to jails as banaction"
