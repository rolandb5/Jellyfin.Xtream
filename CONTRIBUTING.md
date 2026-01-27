# Contributing to Jellyfin Xtream Flat View

Thank you for your interest in contributing! This fork adds several enhancements to the original [Jellyfin.Xtream](https://github.com/Kevinjil/Jellyfin.Xtream) plugin.

---

## Features in This Fork

### Implemented Features

1. **Flat View** (v0.9.1.0)
   - Display all series/movies in one alphabetical list
   - Bypass category folders for faster browsing
   - Optional feature (can be disabled)

2. **Eager Caching** (v0.9.5.0+)
   - Pre-fetch and cache all series data upfront
   - Automatically populate Jellyfin database
   - Instant browsing (no API delays)

3. **Unicode Pipe Support** (v0.9.4.x)
   - Handle Unicode pipe characters (┃, │, ｜) in titles
   - Enhanced title parsing

4. **Bug Fixes**
   - Missing episodes fix (cache invalidation)
   - Malformed JSON handling (v0.9.5.3)
   - Clear Cache DB cleanup (v0.9.5.2)
   - UI error handling improvements

---

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- **[Documentation Index](docs/INDEX.md)** - Start here for navigation
- **[Project Context](docs/reference/PROJECT_CONTEXT.md)** - Project overview and history
- **[Build Errors Prevention](docs/reference/BUILD_ERRORS_PREVENTION.md)** - Common issues and solutions

### Feature Documentation

Each feature has detailed documentation in `docs/features/<feature-name>/`:

- `REQUIREMENTS.md` - Problem statement, user stories, requirements
- `ARCHITECTURE.md` - Design decisions, components, data flow
- `IMPLEMENTATION.md` - Code changes, technical details
- `TEST_PLAN.md` - Manual test cases
- `CHANGELOG.md` - Version history

**Example:** See [docs/features/04-eager-caching/](docs/features/04-eager-caching/) for comprehensive eager caching documentation.

---

## Development Setup

### Prerequisites

- .NET 9.0 SDK
- Git
- Docker (for testing with Jellyfin)

### Clone and Build

```bash
# Clone the repository
git clone https://github.com/rolandb5/Jellyfin.Xtream.git
cd Jellyfin.Xtream

# Build the plugin
dotnet build Jellyfin.Xtream/Jellyfin.Xtream.csproj
```

### Testing

```bash
# Copy DLL to Jellyfin container
docker cp bin/Debug/net9.0/Jellyfin.Xtream.dll \
  jellyfin:/config/plugins/Jellyfin.Xtream_0.9.5.3/

# Fix permissions
docker exec jellyfin chown -R abc:abc /config/plugins/Jellyfin.Xtream_0.9.5.3/

# Restart Jellyfin
docker restart jellyfin
```

---

## Code Style

### Build Requirements

- **No warnings allowed:** Project uses `TreatWarningsAsErrors=true`
- **StyleCop enabled:** Follow C# coding conventions
- **All warnings must be fixed** before committing

### Common Issues

```csharp
// ❌ Avoid
if (collection.Any()) { }

// ✅ Use
if (collection.Count > 0) { }

// ❌ Avoid trailing whitespace
public void Method() {
}

// ✅ No trailing whitespace
public void Method() {
}
```

---

## Making Changes

### 1. Create a Feature Branch

```bash
git checkout -b feature/my-new-feature
```

### 2. Make Your Changes

- Write code following existing conventions
- Add comments for complex logic
- Update relevant documentation in `docs/`

### 3. Build and Test

```bash
# Build
dotnet build Jellyfin.Xtream/Jellyfin.Xtream.csproj

# Test manually in Jellyfin
# (See Testing section above)
```

### 4. Commit

```bash
git add <specific-files>
git commit -m "Brief description of changes

More detailed explanation if needed.

Fixes #123"
```

### 5. Push and Create PR

```bash
git push origin feature/my-new-feature
```

Then create a Pull Request on GitHub with:
- Clear description of what changed
- Why the change is needed
- How to test it
- Screenshots (for UI changes)

---

## Contribution Guidelines

### What We Accept

✅ **Bug fixes** - Issues that cause incorrect behavior
✅ **Performance improvements** - Measurable speed or memory improvements
✅ **Documentation improvements** - Clarifications, corrections, examples
✅ **New features** - Discuss in an issue first before implementing

### What We Don't Accept

❌ **Breaking changes** - Must maintain backward compatibility
❌ **Large refactorings** - Without discussion and clear benefit
❌ **Style-only changes** - Focus on functionality
❌ **Untested changes** - Must be manually tested

### Before Submitting

- [ ] Code builds without warnings
- [ ] Manual testing completed
- [ ] Documentation updated (if applicable)
- [ ] Commit messages are clear and descriptive
- [ ] No unrelated changes included

---

## Documentation Contributions

We welcome documentation improvements! When contributing docs:

1. **Location:** Place docs in appropriate `docs/` subdirectory
2. **Format:** Use markdown (.md files)
3. **Structure:** Follow existing templates (see `docs/features/` examples)
4. **Links:** Use relative links within documentation
5. **Code examples:** Use proper syntax highlighting

---

## Questions?

- **Issues:** Open an issue on GitHub
- **Discussions:** Use GitHub Discussions
- **Documentation:** Check `docs/INDEX.md` first

---

## Upstream Contributions

This fork aims to contribute features back to [Kevinjil/Jellyfin.Xtream](https://github.com/Kevinjil/Jellyfin.Xtream). If you're interested in helping with upstream contributions, please reach out.

---

## License

This project maintains the original GPLv3 license from [Jellyfin.Xtream](https://github.com/Kevinjil/Jellyfin.Xtream).

---

**Thank you for contributing!** 🎉
