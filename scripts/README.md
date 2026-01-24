# Scripts

## pre-commit-check.sh

Pre-commit hook script that checks for common build errors before committing.

### Installation

```bash
# Install as git hook (recommended)
make install-hooks

# Or manually:
chmod +x scripts/pre-commit-check.sh
mkdir -p .git/hooks
echo '#!/bin/sh' > .git/hooks/pre-commit
echo 'exec bash scripts/pre-commit-check.sh' >> .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### Manual Usage

```bash
# Run before committing
./scripts/pre-commit-check.sh
```

### What It Checks

- ✅ Trailing whitespace in staged files
- ✅ Build succeeds (`dotnet build --configuration Release`)

### Exit Codes

- `0` - All checks passed
- `1` - Checks failed (fix errors before committing)

---

## Makefile Targets

See root `Makefile` for available targets:

- `make check` - Run all checks (fix whitespace + build)
- `make fix-whitespace` - Remove trailing whitespace
- `make build` - Build the project
- `make install-hooks` - Install pre-commit hook
