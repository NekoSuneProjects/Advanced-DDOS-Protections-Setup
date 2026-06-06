#!/usr/bin/env bash
# bootstrap.sh — one-liner installer.
# Usage:
#   curl -sSL https://raw.githubusercontent.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup/main/bootstrap.sh | sudo bash
# Source: https://github.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup
#
# What it does:
#   1. git-clones the repo into /opt/ddos-protect
#   2. runs install.sh
#
# Re-run safely to upgrade — clone is fast-forwarded.
set -euo pipefail

REPO_URL="${DDOS_REPO:-https://github.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup.git}"
REPO_BRANCH="${DDOS_BRANCH:-main}"
PREFIX="${DDOS_PREFIX:-/opt/ddos-protect}"

if (( EUID != 0 )); then
    echo "bootstrap.sh must be run as root (try: curl ... | sudo bash)" >&2
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "git is required."
    if   command -v apt-get >/dev/null; then apt-get update -qq && apt-get install -y git
    elif command -v dnf     >/dev/null; then dnf install -y git
    elif command -v yum     >/dev/null; then yum install -y git
    elif command -v pacman  >/dev/null; then pacman -S --noconfirm git
    elif command -v apk     >/dev/null; then apk add --no-cache git
    elif command -v zypper  >/dev/null; then zypper -n install git
    elif command -v brew    >/dev/null; then sudo -u "${SUDO_USER:-$USER}" brew install git
    else
        echo "Install git manually then re-run." >&2; exit 1
    fi
fi

if [[ -d "$PREFIX/.git" ]]; then
    echo "[bootstrap] updating existing checkout at $PREFIX"
    git -C "$PREFIX" fetch --quiet --depth=1 origin "$REPO_BRANCH"
    git -C "$PREFIX" reset --hard "origin/$REPO_BRANCH"
else
    echo "[bootstrap] cloning $REPO_URL -> $PREFIX"
    rm -rf "$PREFIX"
    git clone --depth=1 --branch "$REPO_BRANCH" "$REPO_URL" "$PREFIX"
fi

chmod +x "$PREFIX/install.sh" "$PREFIX/uninstall.sh" \
    "$PREFIX"/linux/modules/*.sh "$PREFIX"/macos/modules/*.sh 2>/dev/null || true

exec bash "$PREFIX/install.sh" "$@"
