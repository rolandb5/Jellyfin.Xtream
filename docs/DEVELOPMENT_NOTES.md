# Development Notes & Learnings

> **Note:** This file is excluded from Git (see `.gitignore`). It's for local documentation only.

## Project Overview

This is a fork of [Jellyfin.Xtream](https://github.com/Kevinjil/Jellyfin.Xtream) with additional features:
- **Flat Series View** - Shows all series directly without category folders
- **Flat VOD View** - Shows all movies directly without category folders
- **Country Code Prefix Filtering** - Automatically removes prefixes like "| NL |" from series names for better metadata matching

## What We Built

### 1. Flat Series View Feature
- **Location:** `Jellyfin.Xtream/SeriesChannel.cs`
- **Method:** `GetAllSeriesFlattened()`
- **Configuration:** `PluginConfiguration.FlattenSeriesView` (boolean)
- **UI:** Checkbox in Series configuration page (`XtreamSeries.html` + `XtreamSeries.js`)

**How it works:**
- When `FlattenSeriesView` is enabled, `GetChannelItems()` returns all series from all selected categories directly
- Series are sorted alphabetically
- Seasons and episodes remain organized under each series

### 2. Flat VOD View Feature
- **Location:** `Jellyfin.Xtream/VodChannel.cs`
- **Method:** `GetAllStreamsFlattened()`
- **Configuration:** `PluginConfiguration.FlattenVodView` (boolean)
- **UI:** Checkbox in VOD configuration page (`XtreamVod.html` + `XtreamVod.js`)

**How it works:**
- Similar to flat series view, but for VOD (movies)
- All movies from selected categories appear directly without category folders

### 3. Episodes Fix
- **Problem:** Episodes weren't showing when clicking on seasons
- **Solution:** Fixed `GetEpisodes()` method in `StreamService.cs`
  - Added configuration check (consistency with `GetSeasons`)
  - Used `TryGetValue` for safe dictionary access
  - Added check for non-empty episodes collection (`Count > 0`)

### 4. Country Code Prefix Filtering
- **Location:** `Jellyfin.Xtream/Service/StreamService.cs` → `ParseName()` method
- **Pattern:** Removes prefixes like `| NL |`, `| DE |`, `| FR |`, etc.
- **Regex:** `^\|\s*[A-Z]{2,3}\s*\|`
- **Purpose:** Improves metadata matching with TMDB/TVDB by cleaning series names

## How We Built It

### Development Workflow

1. **Fork & Setup**
   - Forked original repository
   - Set up local development environment
   - Created feature branch: `feature/flat-series-view`

2. **Implementation Steps**
   - Added configuration properties (`FlattenSeriesView`, `FlattenVodView`)
   - Modified channel classes to support flat view
   - Updated UI configuration pages
   - Fixed bugs (episodes not showing, trailing whitespace, etc.)

3. **CI/CD Setup**
   - Created GitHub Actions workflow (`.github/workflows/publish.yaml`)
   - Set up automatic builds on release events
   - Configured GitHub Pages for plugin repository
   - Fixed workflow issues (upload URL handling, overwrite support)

### Key Files Modified

**Configuration:**
- `Jellyfin.Xtream/Configuration/PluginConfiguration.cs` - Added boolean flags
- `Jellyfin.Xtream/Configuration/Web/XtreamSeries.html` - Added checkbox UI
- `Jellyfin.Xtream/Configuration/Web/XtreamSeries.js` - Added save/load logic
- `Jellyfin.Xtream/Configuration/Web/XtreamVod.html` - Added checkbox UI
- `Jellyfin.Xtream/Configuration/Web/XtreamVod.js` - Added save/load logic

**Core Logic:**
- `Jellyfin.Xtream/SeriesChannel.cs` - Flat series view implementation
- `Jellyfin.Xtream/VodChannel.cs` - Flat VOD view implementation
- `Jellyfin.Xtream/Service/StreamService.cs` - Episodes fix, prefix filtering

**Build & Release:**
- `build.yaml` - Plugin metadata (version, description, changelog)
- `.github/workflows/publish.yaml` - CI/CD workflow

### Version History

- **v0.9.0.0** - Initial fork with flat series view
- **v0.9.1.0** - Added flat VOD view
- **v0.9.1.1** - Fixed missing episodes (first attempt)
- **v0.9.1.2** - Fixed episodes not showing (simplified GetEpisodes)
- **v0.9.1.3** - Fixed episodes with Count > 0 check
- **v0.9.2.0** - Added country code prefix filtering

## Key Learnings

### 1. Jellyfin Plugin Architecture
- Plugins implement `IChannel` interface
- Channel items are created using `ChannelItemInfo`
- Configuration is stored in `PluginConfiguration` class
- UI configuration pages use HTML + JavaScript

### 2. GUID System
- Jellyfin uses GUIDs to identify channel items
- GUIDs encode: prefix, categoryId, seriesId, seasonId
- `StreamService.ToGuid()` and `StreamService.FromGuid()` handle encoding/decoding
- Different prefixes for different item types (Series, Season, Episode, etc.)

### 3. GitHub Actions & CI/CD
- Workflows can be triggered by `release` events or `workflow_dispatch`
- Manual triggers don't have `github.event.release.upload_url` - need to fetch it dynamically
- Use `overwrite: true` in upload actions to allow overwriting existing assets
- GitHub Pages serves `repository.json` for Jellyfin plugin catalog

### 4. Common Issues & Solutions

**Issue:** Workflow not triggering on release
- **Solution:** Ensure workflow file is on default branch (master/main)

**Issue:** Upload failing - "file already exists"
- **Solution:** Use `overwrite: true` in upload action, or delete existing assets first

**Issue:** Episodes not showing
- **Solution:** Check configuration, use safe dictionary access, verify collection is not empty

**Issue:** Build failing - trailing whitespace
- **Solution:** StyleCop analyzer (SA1028) - remove trailing whitespace

**Issue:** Build failing - `.Any()` on ICollection
- **Solution:** Use `.Count > 0` instead for better compatibility

### 5. Plugin Repository Setup
- Create `repository.json` with plugin metadata
- Host on GitHub Pages (gh-pages branch)
- Users add repository URL in Jellyfin: `https://username.github.io/repo-name/repository.json`
- **Important:** Plugin GUID must be unique (or users can't install both versions)

## Testing

### Manual Testing Steps
1. Enable flat view in plugin configuration
2. Check that series/movies appear directly (no category folders)
3. Verify seasons and episodes load correctly
4. Check that country code prefixes are removed from names
5. Verify metadata matching works better after prefix removal

### Known Limitations
- Plugin uses same GUID as original (users can't install both simultaneously)
- Flat view shows all series/movies from all selected categories (no filtering by category in flat view)

## Future Improvements

- [ ] Add option to filter by category even in flat view
- [ ] Support for other country code patterns
- [ ] Option to customize prefix removal patterns
- [ ] Better error handling and logging
- [ ] Performance optimization for large catalogs

## Resources

- **Original Plugin:** https://github.com/Kevinjil/Jellyfin.Xtream
- **Jellyfin Plugin Docs:** https://jellyfin.org/docs/general/development/plugins/
- **GitHub Repository:** https://github.com/rolandb5/Jellyfin.Xtream
- **Plugin Repository:** https://rolandb5.github.io/Jellyfin.Xtream/repository.json

## Notes

- All features are backward compatible (opt-in via configuration)
- Default behavior matches original plugin
- Code follows existing patterns and style
- StyleCop analyzer enforces code style (no trailing whitespace, etc.)
