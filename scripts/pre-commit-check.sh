#!/bin/bash
# Pre-commit hook to check for common build errors
# Usage: Run this before committing, or install as .git/hooks/pre-commit

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Running pre-commit checks..."

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Not in a git repository, skipping git checks${NC}"
else
    # Check for trailing whitespace in staged files
    echo "Checking for trailing whitespace..."
    if git diff --cached --check --diff-filter=ACM 2>&1 | grep -q "^+.*[[:space:]]$"; then
        echo -e "${RED}❌ ERROR: Trailing whitespace detected in staged files!${NC}"
        echo "Fix with: find . -name '*.cs' -exec sed -i '' 's/[[:space:]]*$//' {} \\;"
        echo "Or unstage files, fix, and stage again."
        exit 1
    fi
    echo -e "${GREEN}✅ No trailing whitespace${NC}"
fi

# Check if dotnet is available
if ! command -v dotnet &> /dev/null; then
    echo -e "${YELLOW}⚠️  dotnet not found, skipping build check${NC}"
    echo -e "${GREEN}✅ Pre-commit checks passed (partial)${NC}"
    exit 0
fi

# Build check
echo "Building project..."
if dotnet build --configuration Release --no-incremental > /tmp/build-output.log 2>&1; then
    echo -e "${GREEN}✅ Build successful${NC}"
    rm -f /tmp/build-output.log
else
    echo -e "${RED}❌ ERROR: Build failed!${NC}"
    echo "Build output:"
    cat /tmp/build-output.log
    rm -f /tmp/build-output.log
    exit 1
fi

echo -e "${GREEN}✅ All pre-commit checks passed!${NC}"
exit 0
