#!/bin/bash
# Run DuoBee test suite

set -e

cd "$(dirname "$0")/.."

echo "Running DuoBee tests..."
xcodebuild test \
    -project DuoBee.xcodeproj \
    -scheme DuoBee \
    -destination 'platform=macOS'

echo ""
echo "Tests completed!"
