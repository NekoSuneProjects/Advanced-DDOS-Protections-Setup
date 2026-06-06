#!/usr/bin/env bash
# macOS 06-cloudflare.sh — same as linux/modules/12-cloudflare.sh, just paths.
# Delegate to the shared logic.
set -euo pipefail
source "${DDOS_SCRIPT_DIR}/lib/ui.sh"

# brew install jq if missing.
USER_NAME="${SUDO_USER:-$USER}"
if ! command -v jq >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        sudo -u "$USER_NAME" brew install jq
    else
        fail "Need jq. Install Homebrew first."
        exit 1
    fi
fi

# Re-use the linux script verbatim — semantics are POSIX.
exec bash "${DDOS_SCRIPT_DIR}/linux/modules/12-cloudflare.sh"
