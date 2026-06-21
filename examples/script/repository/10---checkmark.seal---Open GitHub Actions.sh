#!/usr/bin/env bash
#
# Open the GitHub Actions page for this repository's current branch.
#
# A per-repository script-item: Lanes runs it with the repository folder as the
# working directory and REPO_DIR/REPO_NAME (plus LANE_*) in the environment.
# This replaces the former built-in "Open CI" action.
#
set -euo pipefail

cd "${REPO_DIR:-$PWD}"

url=$(git remote get-url origin 2>/dev/null) || { echo "no 'origin' remote" >&2; exit 1; }
url=${url%.git}

# Normalize the remote (ssh / scp-style / https) to host + owner/repo path.
case "$url" in
    git@*:*)            host=${url#git@}; host=${host%%:*}; path=${url#*:} ;;
    ssh://*)            rest=${url#ssh://}; rest=${rest#*@}; host=${rest%%/*}; path=${rest#*/} ;;
    http://*|https://*) rest=${url#*://}; rest=${rest#*@}; host=${rest%%/*}; path=${rest#*/} ;;
    *) echo "unsupported remote: $url" >&2; exit 1 ;;
esac

owner=${path%%/*}
repo=${path#*/}; repo=${repo%%/*}

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
branch_enc=${branch//\//%2F}   # encode '/' in e.g. feature/foo

if [ -n "$branch_enc" ]; then
    open "https://$host/$owner/$repo/actions?query=branch%3A$branch_enc"
else
    open "https://$host/$owner/$repo/actions"
fi
