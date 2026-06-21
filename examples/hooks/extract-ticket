#!/usr/bin/env bash
# extract-ticket hook: print the ticket key to link to this lane (or nothing).
#
# Lanes runs this when a lane is created and on ⌘R; its trimmed stdout is linked
# to the lane as a ticket (idempotent — re-running never duplicates it). The
# ticket then shows in the lane's Tickets section and is exported to scripts as
# $TICKET_KEY / $TICKET_URL.
#
# This example extracts a leading issue key from the folder name: 2+ uppercase
# letters, a dash, then digits — e.g. "ABC-1234-add-login" -> "ABC-1234".
# It prints nothing when the name doesn't match, so no ticket is linked.
set -euo pipefail
if [[ "$LANE_NAME" =~ ^[A-Z]{2,}-[0-9]+ ]]; then
  printf '%s' "$BASH_REMATCH"
fi
