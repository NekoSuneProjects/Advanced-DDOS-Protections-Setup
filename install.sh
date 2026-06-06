#!/usr/bin/env bash
# install.sh — Linux + macOS entrypoint.
# Detects OS, presents menu, runs selected modules, records snapshot for uninstall.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ui.sh
source "${SCRIPT_DIR}/lib/ui.sh"
# shellcheck source=lib/detect.sh
source "${SCRIPT_DIR}/lib/detect.sh"

OS="$(detect_os)"
case "$OS" in
    linux)
        MOD_DIR="${SCRIPT_DIR}/linux/modules"
        STATE_DIR="${SCRIPT_DIR}/linux/state"
        ;;
    macos)
        MOD_DIR="${SCRIPT_DIR}/macos/modules"
        STATE_DIR="${SCRIPT_DIR}/macos/state"
        ;;
    *)
        echo "Unsupported OS: $(uname -s). Use install.ps1 on Windows." >&2
        exit 1
        ;;
esac

STATE_FILE="${STATE_DIR}/state.json"
mkdir -p "$STATE_DIR"

require_root
banner

DISTRO="$(detect_distro)"
PKG="$(detect_pkg_mgr)"
SERVICES="$(detect_services)"
FW=""
[[ "$OS" == "linux" ]] && FW="$(detect_firewall_backend)"

log info "OS:       ${OS} (${DISTRO})"
log info "Pkg mgr:  ${PKG}"
[[ -n "$FW" ]] && log info "Firewall: ${FW}"
log info "Services: ${SERVICES:-<none detected>}"

# Initialize state.json if absent.
if [[ ! -s "$STATE_FILE" ]]; then
    cat >"$STATE_FILE" <<JSON
{
  "version": "${DDOS_VERSION}",
  "os": "${OS}",
  "distro": "${DISTRO}",
  "host": "$(hostname)",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "modules": []
}
JSON
fi
export DDOS_STATE_FILE="$STATE_FILE"
export DDOS_OS="$OS"
export DDOS_DISTRO="$DISTRO"
export DDOS_PKG="$PKG"
export DDOS_FW="$FW"
export DDOS_SCRIPT_DIR="$SCRIPT_DIR"

# Module list per OS.
if [[ "$OS" == "linux" ]]; then
    MODULES=(
        "01-firewall.sh|Edge firewall + rate-limiting + amp-port blackhole"
        "02-sysctl.sh|Kernel/TCP stack hardening (SYN cookies, RFC1337, rp_filter)"
        "03-fail2ban.sh|fail2ban + jails for SSH, nginx, Apache, MySQL, mail, recidive"
        "04-sshd.sh|SSHd hardening (no-root, key-only suggestion, MaxAuthTries)"
        "05-nginx.sh|nginx hardening (limit_req, limit_conn, slowloris timeouts)"
        "06-apache.sh|Apache hardening (mod_evasive, ServerTokens, TraceEnable)"
        "07-mysql.sh|MySQL/MariaDB hardening (bind-address, max_connect_errors)"
        "08-email.sh|Email hardening (Postfix/Dovecot/Exim: anti-relay, rate limits, SASL jails)"
        "09-rootkit-scan.sh|Backdoor scan (rkhunter + chkrootkit + lynis + ClamAV report)"
        "10-audit.sh|Audit listening ports, SUID, cron, world-writable, authorized_keys"
        "11-unsafe-services.sh|Disable risky services (telnet, rsh, rlogin, avahi, rpcbind, cups)"
        "12-cloudflare.sh|Cloudflare integration (under-attack mode + ban sync)"
        "13-notify.sh|Configure notifications (Discord / Telegram / ntfy / Slack / webhook)"
        "14-monitor.sh|Realtime watchdog (CPU/RAM/network/conn) + auto-alert"
        "15-game-servers.sh|Game / voice-server protection (Minecraft, FiveM, TS3, MCPE, etc.)"
    )
else
    MODULES=(
        "01-pf.sh|pf firewall ruleset + amp-port blackhole"
        "02-sysctl.sh|TCP stack hardening (sysctl net.inet.*)"
        "03-fail2ban.sh|fail2ban via Homebrew + SSHd jail"
        "04-sshd.sh|SSHd hardening"
        "05-audit.sh|Audit listening ports, launchd jobs, autorun items"
        "06-cloudflare.sh|Cloudflare integration (under-attack mode + ban sync)"
        "07-notify.sh|Configure notifications (Discord / Telegram / ntfy / Slack / webhook)"
        "08-monitor.sh|Realtime watchdog (CPU/RAM/network/conn) + auto-alert"
        "09-game-servers.sh|Game / voice-server protection (Minecraft, FiveM, TS3, MCPE, etc.)"
    )
fi

run_module() {
    local entry="$1"
    local file="${entry%%|*}"
    local desc="${entry##*|}"
    local path="${MOD_DIR}/${file}"
    if [[ ! -x "$path" ]] && [[ ! -r "$path" ]]; then
        fail "module not found: ${file}"
        return 1
    fi
    step "$desc"
    if bash "$path"; then
        ok "$file complete"
    else
        local rc=$?
        fail "$file failed (exit $rc)"
        return "$rc"
    fi
}

show_module_menu() {
    local -a labels=()
    local m
    for m in "${MODULES[@]}"; do labels+=( "${m##*|}" ); done
    multi_menu "Select modules to run:" "${labels[@]}"
}

main_menu() {
    local opts=(
        "Full install (all applicable modules)"
        "Choose modules"
        "Dry-run (print what would happen)"
        "Uninstall / restore"
        "Exit"
    )
    menu "Main menu" "${opts[@]}"
}

main() {
    while true; do
        local choice
        choice="$(main_menu)"
        case "$choice" in
            1)
                local m
                for m in "${MODULES[@]}"; do run_module "$m" || true; done
                ok "All modules attempted. State recorded at ${STATE_FILE}"
                break
                ;;
            2)
                local picks
                picks="$(show_module_menu)"
                for i in $picks; do
                    run_module "${MODULES[$((i-1))]}" || true
                done
                ok "Selected modules attempted. State recorded at ${STATE_FILE}"
                break
                ;;
            3)
                step "Dry-run"
                for m in "${MODULES[@]}"; do
                    note "would run: ${m%%|*}  —  ${m##*|}"
                done
                ;;
            4)
                log info "Running uninstaller..."
                exec bash "${SCRIPT_DIR}/uninstall.sh"
                ;;
            5)
                log info "Exit."
                exit 0
                ;;
        esac
    done
}

main "$@"
