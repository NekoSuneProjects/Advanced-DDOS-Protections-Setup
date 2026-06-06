#!/usr/bin/env bash
# macOS 07-notify.sh — delegate to the shared Linux notify module.
set -euo pipefail
exec bash "${DDOS_SCRIPT_DIR}/linux/modules/13-notify.sh"
