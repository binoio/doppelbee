#!/bin/bash
# Build DuoBee from command line
#
# Usage:
#   ./build.sh         # Normal build
#   ./build.sh --clean # Clean build (removes all build artifacts first)

set -e

cd "$(dirname "$0")/.."

# Check if --clean flag is provided
if [[ "$1" == "--clean" ]]; then
    echo "Cleaning build artifacts..."
    xcodebuild clean -project DuoBee.xcodeproj -scheme DuoBee 2>&1 | grep -E "(CLEAN|success|error)" || true
    echo "Clean completed."
    echo ""
fi

echo "Building DuoBee..."
xcodebuild -project DuoBee.xcodeproj \
    -scheme DuoBee \
    -configuration Debug \
    build

echo ""
echo "Build completed successfully!"
echo "App location: ~/Library/Developer/Xcode/DerivedData/DuoBee-*/Build/Products/Debug/DuoBee.app"
