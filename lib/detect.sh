#!/usr/bin/env bash
# lib/detect.sh — OS, distro, package-manager and service detection.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "lib/detect.sh is a library; source it, don't execute it." >&2
    exit 1
fi

detect_os() {
    # echoes one of: linux, macos, unknown
    case "$(uname -s)" in
        Linux*)  echo linux ;;
        Darwin*) echo macos ;;
        *)       echo unknown ;;
    esac
}

detect_distro() {
    # echoes a token like: debian, ubuntu, rhel, fedora, centos, arch, alpine, suse, macos, unknown
    if [[ "$(detect_os)" == "macos" ]]; then
        echo macos; return
    fi
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID,,}" in
            debian|ubuntu|linuxmint|raspbian|pop) echo debian ;;
            rhel|centos|rocky|almalinux|ol)       echo rhel ;;
            fedora)                                echo fedora ;;
            arch|manjaro|endeavouros)              echo arch ;;
            alpine)                                echo alpine ;;
            opensuse*|sles)                        echo suse ;;
            *)                                     echo "${ID,,}" ;;
        esac
        return
    fi
    echo unknown
}

detect_pkg_mgr() {
    # echoes: apt, dnf, yum, pacman, apk, zypper, brew, unknown
    if   command -v apt-get >/dev/null 2>&1; then echo apt
    elif command -v dnf     >/dev/null 2>&1; then echo dnf
    elif command -v yum     >/dev/null 2>&1; then echo yum
    elif command -v pacman  >/dev/null 2>&1; then echo pacman
    elif command -v apk     >/dev/null 2>&1; then echo apk
    elif command -v zypper  >/dev/null 2>&1; then echo zypper
    elif command -v brew    >/dev/null 2>&1; then echo brew
    else echo unknown
    fi
}

detect_firewall_backend() {
    # Linux only. echoes: nftables, iptables, ufw, none
    if command -v nft       >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then
        echo nftables
    elif command -v ufw     >/dev/null 2>&1; then
        echo ufw
    elif command -v iptables >/dev/null 2>&1; then
        echo iptables
    else
        echo none
    fi
}

has_service() {
    # has_service nginx   → 0 if a unit or process by that name exists, 1 otherwise.
    local name="$1"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files "${name}.service" 2>/dev/null | grep -q "${name}.service"; then
            return 0
        fi
    fi
    if command -v rc-service >/dev/null 2>&1; then
        rc-service -l 2>/dev/null | grep -qx "$name" && return 0
    fi
    if command -v launchctl >/dev/null 2>&1; then
        launchctl list 2>/dev/null | awk '{print $3}' | grep -qi "$name" && return 0
    fi
    command -v "$name" >/dev/null 2>&1 && return 0
    pgrep -x "$name" >/dev/null 2>&1
}

detect_services() {
    # echoes a space-separated list of detected services from the set we care about.
    local detected=() s
    for s in sshd nginx apache2 httpd mysqld mariadb postgres docker; do
        if has_service "$s"; then detected+=( "$s" ); fi
    done
    printf '%s\n' "${detected[*]}"
}

detect_listening_udp_ports() {
    # echoes space-separated list of UDP ports we are listening on.
    # Used to decide which amplification source ports are safe to blackhole.
    if command -v ss >/dev/null 2>&1; then
        ss -lunH 2>/dev/null | awk '{print $5}' | awk -F: '{print $NF}' | sort -u | tr '\n' ' '
    elif command -v netstat >/dev/null 2>&1; then
        netstat -lun 2>/dev/null | awk '/^udp/ {print $4}' | awk -F: '{print $NF}' | sort -u | tr '\n' ' '
    fi
}
