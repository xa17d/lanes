#!/usr/bin/env bash
set -euo pipefail

# Run from the script's own directory so the relative paths below resolve
# regardless of where it's invoked from.
cd "$(dirname "$0")"

# Build
xcodebuild -project Lanes.xcodeproj -scheme Lanes -configuration Debug \
  -derivedDataPath ./.build build

# Launch the built app (only reached if the build above succeeded).
open ./.build/Build/Products/Debug/Lanes.app
