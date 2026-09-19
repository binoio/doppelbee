#!/bin/bash
# Run DoppelBee app
#
# Usage:
#   ./run.sh              # Find and run existing build, build if not found
#   ./run.sh --build      # Build then run
#   ./run.sh --clean      # Clean build then run
#   ./run.sh --kill       # Kill running instance, clean build, then run

set -e

cd "$(dirname "$0")/.."

# Kill any running instances if --kill flag is provided
if [[ "$1" == "--kill" ]]; then
    echo "Killing any running DoppelBee instances..."
    killall DoppelBee 2>/dev/null || true
    echo "Performing clean build..."
    ./scripts/build.sh --clean
elif [[ "$1" == "--clean" ]]; then
    echo "Performing clean build..."
    ./scripts/build.sh --clean
elif [[ "$1" == "--build" ]]; then
    ./scripts/build.sh
fi

# Find the app in DerivedData
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/DoppelBee-*/Build/Products/Debug/DoppelBee.app -maxdepth 0 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "DoppelBee.app not found. Building first..."
    ./scripts/build.sh
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/DoppelBee-*/Build/Products/Debug/DoppelBee.app -maxdepth 0 2>/dev/null | head -1)
fi

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find DoppelBee.app"
    exit 1
fi

echo "Launching DoppelBee from: $APP_PATH"
open "$APP_PATH"
