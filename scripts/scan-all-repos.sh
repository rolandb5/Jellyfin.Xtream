#!/bin/bash
# Scan all rolandb5 repositories for sensitive information
# Usage: ./scripts/scan-all-repos.sh

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TEMP_DIR=$(mktemp -d)
REPO_OWNER="rolandb5"

echo "🔍 Scanning all $REPO_OWNER repositories for sensitive information..."
echo ""

# Get list of all repositories
echo "Fetching repository list..."
if ! REPOS=$(gh repo list $REPO_OWNER --limit 100 --json name,isPrivate --jq '.[] | "\(.name)|\(.isPrivate)"' 2>&1); then
    echo "Error fetching repository list: $REPOS"
    exit 1
fi

TOTAL_ISSUES=0
REPOS_WITH_ISSUES=0

while IFS='|' read -r REPO_NAME IS_PRIVATE; do
    echo "📦 Scanning: $REPO_NAME ($(if [ "$IS_PRIVATE" = "true" ]; then echo "private"; else echo "public"; fi))"
    
    REPO_DIR="$TEMP_DIR/$REPO_NAME"
    ISSUES_FOUND=0
    
    # Clone repository
    if git clone --quiet "https://github.com/$REPO_OWNER/$REPO_NAME.git" "$REPO_DIR" 2>/dev/null; then
        cd "$REPO_DIR"
        
        # Check for email addresses (excluding example.com)
        EMAIL_COUNT=$(git grep -iE "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" -- ':!*.md' ':!*.example' ':!*.txt' 2>/dev/null | grep -vE "@example\.com|YOUR_EMAIL|your-email|github\.com|noreply" | wc -l | tr -d ' ')
        if [ "$EMAIL_COUNT" -gt 0 ]; then
            echo -e "  ${RED}❌ Found $EMAIL_COUNT email address(es)${NC}"
            git grep -iE "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" -- ':!*.md' ':!*.example' ':!*.txt' 2>/dev/null | grep -vE "@example\.com|YOUR_EMAIL|your-email|github\.com|noreply" | head -3 | sed 's/^/    /'
            ISSUES_FOUND=$((ISSUES_FOUND + EMAIL_COUNT))
        fi
        
        # Check for private IP addresses
        IP_COUNT=$(git grep -E "\b(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)\d+\.\d+" -- ':!*.md' ':!*.example' ':!*.txt' 2>/dev/null | grep -vE "YOUR_|192\.168\.1\.XXX|#.*192\.168|10\.11\.0\.0|10\.0\.0\.0" | wc -l | tr -d ' ')
        if [ "$IP_COUNT" -gt 0 ]; then
            echo -e "  ${RED}❌ Found $IP_COUNT IP address(es)${NC}"
            git grep -E "\b(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)\d+\.\d+" -- ':!*.md' ':!*.example' ':!*.txt' 2>/dev/null | grep -vE "YOUR_|192\.168\.1\.XXX|#.*192\.168|10\.11\.0\.0|10\.0\.0\.0" | head -3 | sed 's/^/    /'
            ISSUES_FOUND=$((ISSUES_FOUND + IP_COUNT))
        fi
        
        # Check for hardcoded passwords
        PASSWORD_COUNT=$(git grep -iE "(password|passwd|pwd|secret|token|api[_-]?key)\s*[=:]\s*['\"][^'\"]{3,}['\"]" -- ':!*.md' ':!*.example' ':!*.txt' 2>/dev/null | grep -vE "YOUR_|placeholder|example|temp==>|GITHUB_TOKEN|process\.env" | wc -l | tr -d ' ')
        if [ "$PASSWORD_COUNT" -gt 0 ]; then
            echo -e "  ${RED}❌ Found $PASSWORD_COUNT potential password(s)${NC}"
            git grep -iE "(password|passwd|pwd|secret|token|api[_-]?key)\s*[=:]\s*['\"][^'\"]{3,}['\"]" -- ':!*.md' ':!*.example' ':!*.txt' 2>/dev/null | grep -vE "YOUR_|placeholder|example|temp==>|GITHUB_TOKEN|process\.env" | head -3 | sed 's/^/    /'
            ISSUES_FOUND=$((ISSUES_FOUND + PASSWORD_COUNT))
        fi
        
        # Check for absolute paths with usernames
        PATH_COUNT=$(git grep -E "(/Users/|/home/)[^/]+/" -- ':!*.md' ':!*.example' ':!*.txt' 2>/dev/null | grep -vE "YOUR_|/path/to|example|placeholder" | wc -l | tr -d ' ')
        if [ "$PATH_COUNT" -gt 0 ]; then
            echo -e "  ${RED}❌ Found $PATH_COUNT absolute path(s) with username${NC}"
            git grep -E "(/Users/|/home/)[^/]+/" -- ':!*.md' ':!*.example' ':!*.txt' 2>/dev/null | grep -vE "YOUR_|/path/to|example|placeholder" | head -3 | sed 's/^/    /'
            ISSUES_FOUND=$((ISSUES_FOUND + PATH_COUNT))
        fi
        
        # Check for personal identifiers (roland, rolandb5, backbase)
        IDENTIFIER_COUNT=$(git grep -iE "\b(roland|rolandb5|rolandbo|backbase)\b" -- ':!*.md' ':!*.example' ':!*.txt' 2>/dev/null | grep -vE "rolandb5/Jellyfin|rolandb5/|github\.com/rolandb5|rolandb5\.github\.io" | wc -l | tr -d ' ')
        if [ "$IDENTIFIER_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}⚠️  Found $IDENTIFIER_COUNT personal identifier(s)${NC}"
            git grep -iE "\b(roland|rolandb5|rolandbo|backbase)\b" -- ':!*.md' ':!*.example' ':!*.txt' 2>/dev/null | grep -vE "rolandb5/Jellyfin|rolandb5/|github\.com/rolandb5|rolandb5\.github\.io" | head -3 | sed 's/^/    /'
            ISSUES_FOUND=$((ISSUES_FOUND + IDENTIFIER_COUNT))
        fi
        
        cd - > /dev/null
        
        if [ "$ISSUES_FOUND" -eq 0 ]; then
            echo -e "  ${GREEN}✅ No issues found${NC}"
        else
            REPOS_WITH_ISSUES=$((REPOS_WITH_ISSUES + 1))
            TOTAL_ISSUES=$((TOTAL_ISSUES + ISSUES_FOUND))
        fi
    else
        echo -e "  ${YELLOW}⚠️  Could not clone (may be private or require auth)${NC}"
    fi
    
    echo ""
done <<< "$REPOS"

# Cleanup
rm -rf "$TEMP_DIR"

echo "📊 SCAN SUMMARY"
echo "=============="
echo "Repositories scanned: $(echo "$REPOS" | wc -l | tr -d ' ')"
echo "Repositories with issues: $REPOS_WITH_ISSUES"
echo "Total issues found: $TOTAL_ISSUES"
echo ""

if [ "$TOTAL_ISSUES" -eq 0 ]; then
    echo -e "${GREEN}✅ All repositories are clean!${NC}"
else
    echo -e "${RED}⚠️  Please review the issues above${NC}"
fi
