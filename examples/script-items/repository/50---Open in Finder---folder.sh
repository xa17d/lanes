#\!/usr/bin/env bash
# Reveal this repository in Finder. (Per-repository script-item.)
set -euo pipefail
open -R "${REPO_DIR:-$PWD}"
