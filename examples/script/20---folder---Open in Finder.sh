#!/usr/bin/env bash
# Open this lane's folder in Finder. (Lane-level script-item; cwd = lane dir.)
# Opens the folder itself in a Finder window (not `open -R`, which would only
# select it inside its parent).
set -euo pipefail
open "${LANE_DIR:-$PWD}"
