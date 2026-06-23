#!/usr/bin/env bash
set -euo pipefail

# Build a Release Lanes.app and install it. Defaults to ~/Applications (no admin
# password needed); pass a directory to override, e.g. `./install.sh /Applications`.
# (Lanes is a menu-bar accessory app — copying the .app is the whole "install".)
cd "$(dirname "$0")"

APP="./.build/Build/Products/Release/Lanes.app"
DEST_DIR="${1:-$HOME/Applications}"
DEST="$DEST_DIR/Lanes.app"

# Build (Release, optimized — unlike build-and-run.sh which builds Debug).
xcodebuild -project Lanes.xcodeproj -scheme Lanes -configuration Release \
  -derivedDataPath ./.build build

# Quit a running copy so the overwrite is clean.
osascript -e 'tell application "Lanes" to quit' >/dev/null 2>&1 || true
pkill -x Lanes 2>/dev/null || true
sleep 1

# Install
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

# Launch the installed copy.
open "$DEST"
echo "Installed and launched $DEST"
