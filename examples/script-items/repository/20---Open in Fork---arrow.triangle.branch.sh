#!/usr/bin/env bash
# Open this repository in Fork. (Per-repository script-item; cwd = repo dir.)
set -euo pipefail
open -a "Fork" "${REPO_DIR:-$PWD}"
