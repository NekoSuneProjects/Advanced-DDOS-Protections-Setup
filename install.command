#!/usr/bin/env bash
# install.command — macOS double-click shim that runs install.sh with sudo
# inside a Terminal window.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
exec sudo bash "${DIR}/install.sh" "$@"
