#!/bin/bash
# Pre-commit hook for PolyglotReader
# Runs SwiftLint on staged Swift files and blocks commit if errors exist
#
# INSTALLATION:
# Copy this file to .git/hooks/pre-commit and make executable:
#   cp Scripts/pre-commit-hook.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Pre-commit: Running SwiftLint...${NC}"

# Check if SwiftLint is installed
if which swiftlint > /dev/null; then
    SWIFTLINT_PATH=$(which swiftlint)
elif [ -f "/opt/homebrew/bin/swiftlint" ]; then
    SWIFTLINT_PATH="/opt/homebrew/bin/swiftlint"
elif [ -f "/usr/local/bin/swiftlint" ]; then
    SWIFTLINT_PATH="/usr/local/bin/swiftlint"
else
    echo -e "${YELLOW}⚠️ SwiftLint not found. Skipping lint check.${NC}"
    exit 0
fi

# Get list of staged Swift files
STAGED_SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep "\.swift$" || true)

if [ -z "${STAGED_SWIFT_FILES}" ]; then
    echo -e "${GREEN}✅ No Swift files staged. Skipping lint.${NC}"
    exit 0
fi

echo "Checking ${STAGED_SWIFT_FILES}"

# First, run autocorrect on staged files
echo -e "${BLUE}🔧 Running autocorrect on staged files...${NC}"
for FILE in ${STAGED_SWIFT_FILES}; do
    if [ -f "${FILE}" ]; then
        "${SWIFTLINT_PATH}" --fix --path "${FILE}" > /dev/null 2>&1 || true
        # Re-add the file if it was modified by autocorrect
        git add "${FILE}"
    fi
done

# Now run lint to check for remaining errors
echo -e "${BLUE}📊 Checking for remaining violations...${NC}"

ERROR_COUNT=0
WARNING_COUNT=0

for FILE in ${STAGED_SWIFT_FILES}; do
    if [ -f "${FILE}" ]; then
        LINT_OUTPUT=$("${SWIFTLINT_PATH}" lint --path "${FILE}" 2>&1) || true
        
        FILE_ERRORS=$(echo "${LINT_OUTPUT}" | grep -c "error:" || echo "0")
        FILE_WARNINGS=$(echo "${LINT_OUTPUT}" | grep -c "warning:" || echo "0")
        
        ERROR_COUNT=$((ERROR_COUNT + FILE_ERRORS))
        WARNING_COUNT=$((WARNING_COUNT + FILE_WARNINGS))
        
        if [ "${FILE_ERRORS}" -gt 0 ] || [ "${FILE_WARNINGS}" -gt 0 ]; then
            echo "${LINT_OUTPUT}"
        fi
    fi
done

# Summary and decision
echo ""
if [ "${ERROR_COUNT}" -gt 0 ]; then
    echo -e "${RED}❌ Commit blocked: ${ERROR_COUNT} error(s) found.${NC}"
    echo -e "${RED}   Fix the errors above before committing.${NC}"
    echo -e "${YELLOW}   Tip: Run 'Scripts/swiftlint-autocorrect.sh' to fix auto-correctable issues.${NC}"
    exit 1
elif [ "${WARNING_COUNT}" -gt 0 ]; then
    echo -e "${YELLOW}⚠️ Commit allowed with ${WARNING_COUNT} warning(s).${NC}"
    exit 0
else
    echo -e "${GREEN}✅ All Swift files passed SwiftLint checks!${NC}"
    exit 0
fi
