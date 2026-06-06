#!/usr/bin/env bash
# lib/ui.sh — colored TUI helpers for install.sh / uninstall.sh / modules.
# Source this; do not execute it directly.

# Refuse to be executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "lib/ui.sh is a library; source it, don't execute it." >&2
    exit 1
fi

# ---------- Colors ----------
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
    C_RESET=$'\033[0m'
    C_DIM=$'\033[2m'
    C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
    C_GREY=$'\033[90m'
else
    C_RESET= C_DIM= C_BOLD= C_RED= C_GREEN= C_YELLOW=
    C_BLUE= C_MAGENTA= C_CYAN= C_GREY=
fi

DDOS_VERSION="${DDOS_VERSION:-1.0.0}"

# ---------- Primitives ----------
banner() {
    printf '%s' "${C_CYAN}"
    cat <<'BANNER'
   ___      __                            __
  / _ |____/ /  _____ ____  _______ ___  / /
 / __ / _  / |/ / _ `/ _ \/ __/ -_) _ \/ _/
/_/ |_\_,_/|___/\_,_/_//_/\__/\__/_//_/\__/
   ___  ___  ___  ___    ___           __        __
  / _ \/ _ \/ _ \(_-<   / _ \_______  / /____ __/ /_
 / // / // / // / __/  / ___/ __/ _ \/ __/ -_) __/ __/
/____/____/____/____/_/_/  /_/  \___/\__/\__/\__/\__/
BANNER
    printf '%s' "${C_RESET}"
    printf '   %sAdvanced DDoS Protections Setup%s  %sv%s%s\n' \
        "${C_BOLD}" "${C_RESET}" "${C_DIM}" "${DDOS_VERSION}" "${C_RESET}"
    printf '   %sLinux · macOS · Windows · defensive hardening toolkit%s\n\n' \
        "${C_GREY}" "${C_RESET}"
}

_ts() { date +'%H:%M:%S'; }

log() {
    local level="$1"; shift
    local color tag
    case "$level" in
        info) color="${C_BLUE}"; tag="INFO" ;;
        warn) color="${C_YELLOW}"; tag="WARN" ;;
        err)  color="${C_RED}";    tag="ERR " ;;
        ok)   color="${C_GREEN}";  tag="OK  " ;;
        *)    color="${C_GREY}";   tag="LOG " ;;
    esac
    printf '%s[%s]%s %s%s%s %s\n' \
        "${C_GREY}" "$(_ts)" "${C_RESET}" \
        "${color}" "${tag}" "${C_RESET}" "$*"
}

step() {  printf '\n%s▶%s %s%s%s\n' "${C_CYAN}" "${C_RESET}" "${C_BOLD}" "$*" "${C_RESET}"; }
ok()   {  printf '  %s✔%s %s\n'    "${C_GREEN}" "${C_RESET}" "$*"; }
fail() {  printf '  %s✗%s %s\n'    "${C_RED}"   "${C_RESET}" "$*" >&2; }
note() {  printf '  %s·%s %s\n'    "${C_GREY}"  "${C_RESET}" "$*"; }

# ---------- Input ----------
yesno() {
    # yesno "Question?" [default-yes]
    local prompt="$1" default="${2:-no}" yn hint
    [[ "$default" == "yes" ]] && hint="[Y/n]" || hint="[y/N]"
    while true; do
        printf '%s?%s %s %s%s%s ' \
            "${C_MAGENTA}" "${C_RESET}" "$prompt" "${C_DIM}" "$hint" "${C_RESET}"
        read -r yn || yn=""
        yn="${yn,,}"
        [[ -z "$yn" ]] && yn="$default"
        case "$yn" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) printf '  %sPlease answer y or n.%s\n' "${C_YELLOW}" "${C_RESET}" ;;
        esac
    done
}

menu() {
    # menu "Title" "Opt 1" "Opt 2" ...
    # Echoes selected index (1-based) on stdout.
    local title="$1"; shift
    local -a opts=("$@")
    local i choice
    {
        printf '\n%s%s%s\n' "${C_BOLD}" "$title" "${C_RESET}"
        for i in "${!opts[@]}"; do
            printf '  %s%d)%s %s\n' "${C_CYAN}" "$((i+1))" "${C_RESET}" "${opts[$i]}"
        done
        printf '\n'
    } >&2
    while true; do
        printf '%s>%s Choose [1-%d]: ' \
            "${C_MAGENTA}" "${C_RESET}" "${#opts[@]}" >&2
        read -r choice || choice=""
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#opts[@]} )); then
            printf '%s\n' "$choice"
            return 0
        fi
        printf '  %sInvalid choice.%s\n' "${C_YELLOW}" "${C_RESET}" >&2
    done
}

multi_menu() {
    # multi_menu "Title" "Opt 1" "Opt 2" ...
    # Echoes space-separated selected indices.
    local title="$1"; shift
    local -a opts=("$@")
    local i raw idx
    local -a chosen=()
    {
        printf '\n%s%s%s  %s(comma-separated, e.g. 1,3,4 or "all")%s\n' \
            "${C_BOLD}" "$title" "${C_RESET}" "${C_DIM}" "${C_RESET}"
        for i in "${!opts[@]}"; do
            printf '  %s%d)%s %s\n' "${C_CYAN}" "$((i+1))" "${C_RESET}" "${opts[$i]}"
        done
        printf '\n'
    } >&2
    while true; do
        printf '%s>%s Select: ' "${C_MAGENTA}" "${C_RESET}" >&2
        read -r raw || raw=""
        raw="${raw// /}"
        if [[ "$raw" == "all" ]]; then
            for i in "${!opts[@]}"; do chosen+=( "$((i+1))" ); done
            printf '%s\n' "${chosen[*]}"
            return 0
        fi
        chosen=()
        local ok=1
        IFS=',' read -ra parts <<<"$raw"
        for idx in "${parts[@]}"; do
            if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#opts[@]} )); then
                chosen+=( "$idx" )
            else
                ok=0; break
            fi
        done
        if (( ok && ${#chosen[@]} > 0 )); then
            printf '%s\n' "${chosen[*]}"
            return 0
        fi
        printf '  %sInvalid selection.%s\n' "${C_YELLOW}" "${C_RESET}" >&2
    done
}

# ---------- Guards ----------
require_root() {
    if (( EUID != 0 )); then
        log err "This script must be run as root (try: sudo $0)"
        exit 1
    fi
}

# ---------- Spinner for backgrounded long tasks ----------
spinner() {
    local pid="$1" msg="${2:-working}"
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %s%s%s %s' "${C_CYAN}" "${frames:i++%${#frames}:1}" "${C_RESET}" "$msg"
        sleep 0.08
    done
    printf '\r\033[K'
}
