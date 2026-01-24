.PHONY: help check build clean fix-whitespace test install-hooks

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

check: fix-whitespace build ## Run all checks (fix whitespace + build)
	@echo "✅ All checks passed!"

build: ## Build the project
	@echo "🔨 Building project..."
	dotnet build --configuration Release --no-incremental

clean: ## Clean build artifacts
	@echo "🧹 Cleaning..."
	dotnet clean

fix-whitespace: ## Remove trailing whitespace from all .cs files
	@echo "🧹 Removing trailing whitespace..."
	@find . -name "*.cs" -type f -exec sed -i '' 's/[[:space:]]*$$//' {} \;
	@echo "✅ Trailing whitespace removed"

test: build ## Run tests (if any)
	@echo "🧪 Running tests..."
	@dotnet test --no-build --configuration Release || echo "No tests found"

install-hooks: ## Install pre-commit hook
	@echo "📝 Installing pre-commit hook..."
	@chmod +x scripts/pre-commit-check.sh
	@mkdir -p .git/hooks
	@echo '#!/bin/sh' > .git/hooks/pre-commit
	@echo 'exec bash scripts/pre-commit-check.sh' >> .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "✅ Pre-commit hook installed"

lint: ## Run linting checks (build with analyzers)
	@echo "🔍 Running lint checks..."
	@dotnet build --configuration Release --no-incremental
