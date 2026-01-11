#!/bin/bash
# SwiftLint Autocorrect Script for PolyglotReader
# Use this script to automatically fix correctable violations

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Running SwiftLint Autocorrect...${NC}"

# Check if SwiftLint is installed
if which swiftlint > /dev/null; then
    SWIFTLINT_PATH=$(which swiftlint)
elif [ -f "/opt/homebrew/bin/swiftlint" ]; then
    SWIFTLINT_PATH="/opt/homebrew/bin/swiftlint"
elif [ -f "/usr/local/bin/swiftlint" ]; then
    SWIFTLINT_PATH="/usr/local/bin/swiftlint"
else
    echo -e "${RED}❌ SwiftLint not found. Install with: brew install swiftlint${NC}"
    exit 1
fi

# Navigate to project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "${SCRIPT_DIR}/.."

# Run autocorrect
if [ -f ".swiftlint.yml" ]; then
    "${SWIFTLINT_PATH}" --fix --config .swiftlint.yml
else
    "${SWIFTLINT_PATH}" --fix
fi

echo -e "${GREEN}✅ Autocorrect completed!${NC}"
echo ""

# Show remaining issues
echo -e "${BLUE}📊 Checking for remaining violations...${NC}"
if [ -f ".swiftlint.yml" ]; then
    REMAINING=$("${SWIFTLINT_PATH}" lint --config .swiftlint.yml 2>&1 | tail -1)
else
    REMAINING=$("${SWIFTLINT_PATH}" lint 2>&1 | tail -1)
fi

echo "${REMAINING}"
