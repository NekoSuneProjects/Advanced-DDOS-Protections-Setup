#!/usr/bin/env bash
# uninstall-remote.sh — one-liner reversal.
# Usage:
#   curl -sSL https://raw.githubusercontent.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup/main/uninstall-remote.sh | sudo bash
set -euo pipefail
PREFIX="${DDOS_PREFIX:-/opt/ddos-protect}"
if [[ ! -x "$PREFIX/uninstall.sh" ]]; then
    echo "No install found at $PREFIX. Pass DDOS_PREFIX=/your/path if you cloned elsewhere." >&2
    exit 1
fi
exec bash "$PREFIX/uninstall.sh" "$@"
