#!/usr/bin/env bash
# update-lane-description hook: print the lane's one-line description (or nothing
# to leave it unchanged).
#
# Lanes runs this when a lane is created, on ⌘R, and — because the output sets a
# {{refresh:…}} interval below — automatically when the lane/list is shown and
# that long has elapsed. The output may embed directives:
#   {{badge:color:text}}  a colored status pill
#   {{refresh:duration}}  re-run cadence (30s / 30m / 2h / 1d)
# It also receives $LANE_DIR/$LANE_NAME/$LANE_ID and $TICKET_KEY/$TICKET_URL.
#
# This example reports git working-tree status for the lane, refreshed every 10m.
set -euo pipefail
cd "$LANE_DIR"
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git")
if git diff --quiet 2>/dev/null; then
  echo "{{refresh:10m}} {{badge:green:clean}} on $branch"
else
  echo "{{refresh:10m}} {{badge:orange:uncommitted changes}} on $branch"
fi
