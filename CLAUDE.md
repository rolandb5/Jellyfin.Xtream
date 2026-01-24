# Jellyfin Xtream Flat View - Project Context

## Build & Release Process

### Versioning
- **Plugin version** is defined in `build.yaml` (line 4): `version: "X.Y.Z.W"`
- This is what Jellyfin displays in the plugin catalog
- Git tags (e.g., `v0.9.1.4`) should match the `build.yaml` version

### Building Locally
```bash
# Requires .NET 9.0 SDK
dotnet build Jellyfin.Xtream/Jellyfin.Xtream.csproj
```

### Release Workflow
1. Update version in `build.yaml`
2. Update changelog in `build.yaml`
3. Commit and push to `master`
4. Create git tag: `git tag v0.9.1.4`
5. Push tag: `git push origin v0.9.1.4`
6. Create GitHub release: `gh release create v0.9.1.4 --repo rolandb5/Jellyfin.Xtream --title "v0.9.1.4" --notes "..."`
7. GitHub Actions (`.github/workflows/build.yaml`) automatically:
   - Builds the plugin
   - Uploads `jellyfin-xtream-flat-view_X.Y.Z.W.zip` to the release
   - Generates checksums (md5, sha256)
   - Updates the plugin manifest repository

### Code Analysis
- Project uses `TreatWarningsAsErrors` - all warnings fail the build
- StyleCop and other analyzers are enabled
- Common issues:
  - CA1860: Use `Count > 0` instead of `Any()`
  - SA1028: Trailing whitespace

## Key Files

| File | Purpose |
|------|---------|
| `build.yaml` | Plugin metadata, version, changelog (what Jellyfin sees) |
| `Jellyfin.Xtream.csproj` | .NET project file, assembly version |
| `Service/StreamService.cs` | Core service, includes `ParseName()` for title cleaning |
| `VodChannel.cs` | VOD/Movies channel implementation |
| `SeriesChannel.cs` | Series channel implementation |
| `Configuration/PluginConfiguration.cs` | Plugin settings (FlattenSeriesView, FlattenVodView, etc.) |

## Title Parsing (ParseName)

Located in `Service/StreamService.cs`, the `ParseName()` method strips tags from titles:
- `[TAG]` - Square brackets
- `|TAG|` - ASCII pipe
- `┃TAG┃` - Unicode box drawing heavy vertical (U+2503)
- `│TAG│` - Unicode box drawing light vertical (U+2502)
- `｜TAG｜` - Unicode fullwidth vertical line (U+FF5C)
- Handles spaces inside pipes: `| TAG |`, `┃ NL ┃`

## Git Remotes

- `origin`: https://github.com/rolandb5/Jellyfin.Xtream.git (your fork)
- `upstream`: https://github.com/Kevinjil/Jellyfin.Xtream.git (original repo)

## Jellyfin Plugin Installation

Users add this repository URL to Jellyfin's plugin repositories:
```
https://raw.githubusercontent.com/rolandb5/Jellyfin.Xtream/master/manifest.json
```
