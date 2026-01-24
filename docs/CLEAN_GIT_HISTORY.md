# Cleaning Sensitive Information from Git History

This guide explains how to remove sensitive information (passwords, IP addresses, etc.) from git history using BFG Repo-Cleaner.

## ⚠️ Important Warnings

1. **This rewrites git history** - All commit hashes will change
2. **Force push required** - You'll need to `git push --force`
3. **Collaborators affected** - Anyone who cloned the repo will need to re-clone or rebase
4. **Backup first** - Make sure you have a backup of your repo

## Prerequisites

- Java installed (`java -version` should work)
- BFG Repo-Cleaner JAR (script will download if needed)

## Quick Start

```bash
# Run the cleaning script
./scripts/clean-git-history.sh

# Review changes
git log --all
git log -p | grep -i "[redacted-ip]\|temp"  # Should find nothing

# Force push (if satisfied)
git push origin master --force
```

## What Gets Replaced

The script uses `scripts/bfg-replace.txt` which contains:
- `[redacted-ip]` → `YOUR_JELLYFIN_HOST`
- `temp` → `YOUR_SSH_PASSWORD`

You can edit `scripts/bfg-replace.txt` to add more replacements.

## Manual Process (If Script Fails)

### Step 1: Download BFG

```bash
curl -L -o /tmp/bfg.jar https://repo1.maven.org/maven2/com/madgag/bfg/1.14.0/bfg-1.14.0.jar
```

### Step 2: Create Bare Clone

```bash
cd /tmp
git clone --mirror /path/to/your/repo jellyfin-xtream-bare.git
```

### Step 3: Run BFG

```bash
cd /tmp/jellyfin-xtream-bare.git
java -jar /tmp/bfg.jar --replace-text /path/to/bfg-replace.txt .
```

### Step 4: Clean Up

```bash
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

### Step 5: Update Original Repo

```bash
cd /path/to/your/repo
git fetch /tmp/jellyfin-xtream-bare.git
git reset --hard FETCH_HEAD
```

### Step 6: Force Push

```bash
git push origin master --force
```

## Alternative: Using git filter-branch

If BFG doesn't work, you can use built-in git commands:

```bash
# Remove file from all commits
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch scripts/remove-plugin-from-jellyfin.sh" \
  --prune-empty --tag-name-filter cat -- --all

# Replace strings in all commits
git filter-branch --force --tree-filter \
  "find . -type f -exec sed -i '' 's/[redacted-ip]/YOUR_JELLYFIN_HOST/g' {} +" \
  --prune-empty --tag-name-filter cat -- --all

git filter-branch --force --tree-filter \
  "find . -type f -exec sed -i '' 's/temp/YOUR_SSH_PASSWORD/g' {} +" \
  --prune-empty --tag-name-filter cat -- --all

# Clean up
git for-each-ref --format="delete %(refname)" refs/original | git update-ref --stdin
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

## Verification

After cleaning, verify sensitive data is gone:

```bash
# Search for sensitive strings in history
git log --all -p | grep -i "[redacted-ip]"
git log --all -p | grep -i "temp"

# Should return nothing
```

## After Force Pushing

1. **Update local clones:**
   ```bash
   # On other machines
   git fetch origin
   git reset --hard origin/master
   ```

2. **Or re-clone:**
   ```bash
   rm -rf old-clone
   git clone https://github.com/rolandb5/Jellyfin.Xtream.git
   ```

## Prevention

To prevent this in the future:

1. **Use `.gitignore`** for files with sensitive data
2. **Use environment variables** instead of hardcoded values
3. **Use `.example` files** for templates
4. **Review before committing** - Run `git diff` before `git add`

---

*Last updated: 2026-01-24*
