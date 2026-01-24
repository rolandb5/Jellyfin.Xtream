# Security Guidelines

## Preventing Sensitive Information in Git

This document outlines best practices to prevent accidentally committing sensitive information to the repository.

## What to Never Commit

### 1. Email Addresses
- ❌ **Never**: `rolandbo@backbase.com`, `user@company.com`
- ✅ **Use**: `your-email@example.com`, `YOUR_EMAIL`, placeholders

### 2. IP Addresses
- ❌ **Never**: `[redacted-ip]`, `[redacted-ip]`
- ✅ **Use**: `YOUR_JELLYFIN_HOST`, `192.168.1.XXX`, `localhost`

### 3. Passwords, Tokens, API Keys
- ❌ **Never**: `password="temp"`, `api_key="abc123"`
- ✅ **Use**: `YOUR_PASSWORD`, environment variables, `.env` files (gitignored)

### 4. Absolute Paths with Usernames
- ❌ **Never**: `/Users/rolandbo@backbase.com/Documents/...`
- ✅ **Use**: Relative paths, `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`, `/path/to/repo`

### 5. Internal Hostnames/Domains
- ❌ **Never**: `internal-server.company.local`
- ✅ **Use**: `your-server.local`, `example.com`

## Protection Mechanisms

### 1. Cursor Rules (`.cursorrules`)
AI assistants (like Cursor) will automatically check for sensitive information before suggesting code changes.

### 2. Pre-Commit Hook
The `scripts/pre-commit-check.sh` script automatically checks for:
- Email addresses (excluding examples)
- Private IP addresses
- Absolute paths with usernames
- Potential passwords

**Install the hook:**
```bash
make install-hooks
# Or manually:
cp scripts/pre-commit-check.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### 3. `.gitignore`
Files containing sensitive information should be added to `.gitignore`:
- `scripts/remove-plugin-from-jellyfin.sh` (contains IPs/passwords)
- `CLAUDE.local.md` (private notes)
- `.env*` files
- `*.local.*` files

### 4. Example Files
For files that need to contain configuration but shouldn't have real values:
- Create `.example` versions: `config.json.example`
- Document placeholders clearly
- Never commit the actual config file

## Safe Patterns

### Scripts
```bash
# ✅ Good: Relative paths
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ✅ Good: Environment variables
JELLYFIN_HOST="${JELLYFIN_HOST:-localhost}"
SSH_PASSWORD="${SSH_PASSWORD}"

# ✅ Good: Placeholders in examples
# Replace YOUR_EMAIL with your actual email
```

### Documentation
```markdown
# ✅ Good: Placeholders
```bash
cd "/path/to/repo"
./scripts/setup.sh
```

# ❌ Bad: Real paths
```bash
cd "/Users/rolandbo@backbase.com/Documents/Coding Projects/..."
```
```

## If You Accidentally Commit Sensitive Information

### Immediate Actions
1. **Don't panic** - but act quickly
2. **Remove from working directory**: Add to `.gitignore` and remove from tracking
3. **Clean git history**: Use `scripts/clean-git-history-filter-branch.sh`
4. **Force push**: `git push origin master --force` (⚠️ coordinate with team)

### Cleaning Git History
See `docs/CLEAN_GIT_HISTORY.md` for detailed instructions.

**Quick reference:**
```bash
# 1. Update bfg-replace.txt with sensitive strings
# 2. Run cleaning script
./scripts/clean-git-history-filter-branch.sh

# 3. Clean up and force push
git for-each-ref --format="delete %(refname)" refs/original | git update-ref --stdin
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push origin master --force
```

## Checklist Before Committing

- [ ] No email addresses (except `@example.com` or placeholders)
- [ ] No IP addresses (except placeholders)
- [ ] No passwords, tokens, or API keys
- [ ] No absolute paths with usernames
- [ ] Scripts use relative paths or environment variables
- [ ] Sensitive files are in `.gitignore`
- [ ] Example files use clear placeholders
- [ ] Pre-commit hook passes (`make check` or `./scripts/pre-commit-check.sh`)

## Related Documentation

- `.cursorrules` - AI assistant rules
- `docs/CLEAN_GIT_HISTORY.md` - How to clean git history
- `scripts/pre-commit-check.sh` - Pre-commit validation script
- `.gitignore` - Files excluded from git
