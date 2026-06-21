#!/usr/bin/env bash
#
# Open PR — focus the Chrome tab showing this repo's pull/merge request page for
# the current branch, or open it. Replaces the former built-in "Open PR" action,
# including its focus-an-existing-tab behavior.
#
# Per-repository script-item: cwd = repo dir; REPO_DIR/REPO_NAME (plus LANE_*) in
# env. The PR URL is reconstructed from the `origin` remote for GitHub / GitLab /
# Bitbucket; the Chrome Apple Event reuses Lanes' Automation permission.
set -euo pipefail

cd "${REPO_DIR:-$PWD}"

remote=$(git remote get-url origin 2>/dev/null) || { echo "no 'origin' remote" >&2; exit 1; }
remote=${remote%.git}

# Normalize ssh / scp-style / https remotes to host + owner/repo path.
case "$remote" in
    git@*:*)            host=${remote#git@}; host=${host%%:*}; path=${remote#*:} ;;
    ssh://*)            rest=${remote#ssh://}; rest=${rest#*@}; host=${rest%%/*}; path=${rest#*/} ;;
    http://*|https://*) rest=${remote#*://}; rest=${rest#*@}; host=${rest%%/*}; path=${rest#*/} ;;
    *) echo "unsupported remote: $remote" >&2; exit 1 ;;
esac
path=${path%.git}
owner=${path%/*}     # keeps any GitLab subgroup path
slug=${path##*/}

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
enc=${branch//\//%2F}   # encode '/' …
enc=${enc//:/%3A}       # … and ':' for the query value

case "$host" in
    *github*)    url="https://$host/$owner/$slug/pulls?q=is%3Apr+head%3A$enc" ;;
    *gitlab*)    url="https://$host/$owner/$slug/-/merge_requests?scope=all&state=opened&source_branch=$enc" ;;
    *bitbucket*) url="https://bitbucket.org/$owner/$slug/pull-requests/?query=$enc" ;;
    *) echo "unrecognized host: $host" >&2; exit 1 ;;
esac

osascript - "$url" "$url" <<'APPLESCRIPT'
on run argv
    set theSub to item 1 of argv
    set theFallback to item 2 of argv
    tell application "Google Chrome"
        set wins to windows
        repeat with w in wins
            set idx to 0
            repeat with t in tabs of w
                set idx to idx + 1
                if (URL of t) contains theSub then
                    set active tab index of w to idx
                    set index of w to 1
                    activate
                    return "focused"
                end if
            end repeat
        end repeat
        if (count of windows) = 0 then make new window
        tell front window to make new tab with properties {URL:theFallback}
        activate
        return "opened"
    end tell
end run
APPLESCRIPT
