#!/bin/bash
# SwiftLint Build Phase Script for PolyglotReader
# Runs SwiftLint during Xcode build process
# NOTE: This script warns but does NOT fail the build

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "🔍 Running SwiftLint..."

# Check if SwiftLint is installed
if which swiftlint > /dev/null; then
    SWIFTLINT_PATH=$(which swiftlint)
elif [ -f "/opt/homebrew/bin/swiftlint" ]; then
    SWIFTLINT_PATH="/opt/homebrew/bin/swiftlint"
elif [ -f "/usr/local/bin/swiftlint" ]; then
    SWIFTLINT_PATH="/usr/local/bin/swiftlint"
else
    echo -e "${YELLOW}⚠️ SwiftLint not found. Install with: brew install swiftlint${NC}"
    exit 0  # Don't fail the build
fi

# Navigate to project root
cd "${SRCROOT}"

# Run SwiftLint
if [ -f ".swiftlint.yml" ]; then
    "${SWIFTLINT_PATH}" lint --config .swiftlint.yml || true
else
    "${SWIFTLINT_PATH}" lint || true
fi

# Always exit successfully - SwiftLint errors are warnings only
echo "✅ SwiftLint check complete"
exit 0
