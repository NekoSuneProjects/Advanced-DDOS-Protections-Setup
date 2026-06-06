#!/usr/bin/env bash
# 06-apache.sh — Apache hardening if Apache (apache2 or httpd) is installed.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"
source "${DDOS_SCRIPT_DIR}/lib/detect.sh"

if ! command -v apache2 >/dev/null 2>&1 && ! command -v httpd >/dev/null 2>&1; then
    note "Apache not installed — skipping"
    exit 0
fi

# Pick distro paths.
if command -v apache2 >/dev/null 2>&1; then
    CONF_DIR=/etc/apache2/conf-available
    DST="$CONF_DIR/ddos-hardening.conf"
    RELOAD="systemctl reload apache2"
    ENABLE_CONF="a2enconf ddos-hardening"
    DISABLE_DEFAULT_MODS=( "a2dismod status info userdir autoindex" )
else
    CONF_DIR=/etc/httpd/conf.d
    DST="$CONF_DIR/ddos-hardening.conf"
    RELOAD="systemctl reload httpd"
    ENABLE_CONF=":"
fi

mkdir -p "$CONF_DIR"
cat > "$DST" <<'CFG'
# Apache hardening — installed by Advanced DDoS Protections Setup.
ServerTokens Prod
ServerSignature Off
TraceEnable Off
FileETag None
KeepAlive On
KeepAliveTimeout 5
MaxKeepAliveRequests 100
Timeout 30
LimitRequestBody 8388608
LimitRequestFields 64
LimitRequestFieldSize 4096
LimitRequestLine 4096

# Drop common L7 attack-tool fingerprints.
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteCond %{HTTP_USER_AGENT} (BOT|KILLER|BYPASS|CFB|CFBUAM|STOMP|RHEX) [NC,OR]
    RewriteCond %{HTTP_USER_AGENT} (masscan|nikto|nmap|sqlmap|nuclei|fuzzer) [NC,OR]
    RewriteCond %{HTTP_USER_AGENT} ^-?$
    RewriteRule .* - [F,L]
</IfModule>

# Disable risky methods.
<Location />
    <LimitExcept GET POST HEAD OPTIONS>
        Require all denied
    </LimitExcept>
</Location>
CFG

# Try to install / enable mod_evasive if available.
case "$(detect_pkg_mgr)" in
    apt)
        apt-get install -y libapache2-mod-evasive >/dev/null 2>&1 || true
        cat > /etc/apache2/mods-available/evasive.conf <<EVA
<IfModule mod_evasive20.c>
    DOSHashTableSize 3097
    DOSPageCount 5
    DOSSiteCount 50
    DOSPageInterval 1
    DOSSiteInterval 1
    DOSBlockingPeriod 60
    DOSLogDir "/var/log/mod_evasive"
</IfModule>
EVA
        mkdir -p /var/log/mod_evasive
        chown www-data:www-data /var/log/mod_evasive 2>/dev/null || true
        a2enmod evasive >/dev/null 2>&1 || true
        ;;
    dnf|yum)
        "$(detect_pkg_mgr)" install -y mod_evasive >/dev/null 2>&1 || true
        ;;
esac

eval "$ENABLE_CONF" >/dev/null 2>&1 || true
if eval "$RELOAD" 2>/tmp/apache-reload.log; then
    ok "Apache hardened (config: $DST)"
else
    fail "Apache reload failed; check /tmp/apache-reload.log"
    exit 1
fi
