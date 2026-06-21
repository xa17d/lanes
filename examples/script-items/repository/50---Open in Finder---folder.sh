#!/usr/bin/env bash
# Open this repository in Finder. (Per-repository script-item.)
# Opens the repo folder itself in a Finder window (not `open -R`, which would
# only select it inside its parent).
set -euo pipefail
open "${REPO_DIR:-$PWD}"
