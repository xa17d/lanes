#!/usr/bin/env bash
#
# Open Terminal here — focus this repository's tagged iTerm2 session, or create
# one with the repository folder as the working directory. Replaces the former
# built-in per-repo "Open Terminal here" action.
#
# Per-repository script-item: cwd = repo dir; REPO_DIR/REPO_NAME (plus LANE_*) in
# env. The session tag includes the repo path so each repo gets its own session.
set -euo pipefail

CWD="${REPO_DIR:-$PWD}"
TAG="repo:${CWD}"
CMD=""   # bare shell

osascript - "«lane:${LANE_ID:-}:${TAG}»" "$CWD" "$CMD" <<'APPLESCRIPT'
on run argv
    set theTag to item 1 of argv
    set theCwd to item 2 of argv
    set theCmd to item 3 of argv
    tell application "iTerm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    set sTag to ""
                    try
                        tell s to set sTag to (variable named "user.lane")
                    end try
                    if sTag is theTag then
                        tell t to select
                        tell s to select
                        select w
                        activate
                        delay 0.15
                        repeat with w2 in windows
                            repeat with t2 in tabs of w2
                                repeat with s2 in sessions of t2
                                    set tg2 to ""
                                    try
                                        tell s2 to set tg2 to (variable named "user.lane")
                                    end try
                                    if tg2 is theTag then
                                        tell t2 to select
                                        tell s2 to select
                                        select w2
                                    end if
                                end repeat
                            end repeat
                        end repeat
                        return "focused"
                    end if
                end repeat
            end repeat
        end repeat
        set newWindow to (create window with default profile)
        tell current session of newWindow
            set variable named "user.lane" to theTag
            write text "cd " & quoted form of theCwd
            if theCmd is not "" then write text theCmd
        end tell
        activate
        return "created"
    end tell
end run
APPLESCRIPT
