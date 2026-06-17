#\!/usr/bin/env bash
# Reveal this lane's folder in Finder. (Lane-level script-item; cwd = lane dir.)
set -euo pipefail
open -R "${LANE_DIR:-$PWD}"
