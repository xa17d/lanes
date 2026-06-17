#\!/usr/bin/env bash
# Open this repository in VS Code. (Per-repository script-item.)
set -euo pipefail
open -a "Visual Studio Code" "${REPO_DIR:-$PWD}"
