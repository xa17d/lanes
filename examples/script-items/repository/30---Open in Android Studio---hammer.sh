#!/usr/bin/env bash
# Open this repository in Android Studio. (Per-repository script-item.)
set -euo pipefail
open -a "Android Studio" "${REPO_DIR:-$PWD}"
