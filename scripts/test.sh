#!/bin/bash
# Run DoppelBee test suite

set -e

cd "$(dirname "$0")/.."

echo "Running DoppelBee tests..."
xcodebuild test \
    -project DoppelBee.xcodeproj \
    -scheme DoppelBee \
    -destination 'platform=macOS'

echo ""
echo "Tests completed!"
