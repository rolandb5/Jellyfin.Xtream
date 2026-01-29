# TVDb Artwork Injection - Changelog

## v0.9.13.0 (2026-01-29)

### Added — Season/Episode Artwork Improvements

- **FIX:** Season artwork now displays correctly
  - `ImageUrl` was computed in season `CreateChannelItemInfo` but never assigned to the return object
  - **Files:** `SeriesChannel.cs` (lines 190-214)

- **FIX:** Episode names now show parsed title instead of hardcoded "Episode N"
  - Was: `Name = $"Episode {episode.EpisodeNum}"`
  - Now: `Name = string.IsNullOrWhiteSpace(parsedName.Title) ? $"Episode {episode.EpisodeNum}" : parsedName.Title`
  - **Files:** `SeriesChannel.cs` (lines 256-258)

- **NEW:** Metadata language preference for TVDb queries
  - TVDb searches now use Jellyfin's server-wide `PreferredMetadataLanguage` setting
  - Injected via `IServerConfigurationManager` in Plugin constructor
  - **Files:** `Plugin.cs`, `Service/SeriesCacheService.cs`

- **NEW:** Enhanced artwork fallback chains
  - **Season:** Xtream season cover → TVDb series poster → Xtream series cover
  - **Episode:** TVDb episode image → Xtream episode → season cover → TVDb series poster → Xtream series cover
  - **Files:** `SeriesChannel.cs` (lines 190-206, 238-243)

- **NEW:** TVDb series ID caching for episode lookups (infrastructure)
  - `GetCachedTvdbSeriesId()` method added
  - TVDb series ID cached alongside image URL during series lookup
  - **Files:** `Service/SeriesCacheService.cs` (lines 601-605, 667-668, 714-718)

### Removed — Per-Episode TVDb Image Lookup (Disabled)

- **DISABLED:** `LookupAndCacheEpisodeImagesAsync()` call removed from `RefreshCacheAsync()`
  - **Reason:** Jellyfin's TVDb plugin `TvdbEpisodeProvider.GetSearchResults()` does not populate `ImageUrl`
  - Episode images require `TvdbEpisodeImageProvider.GetImages(BaseItem)` which needs Jellyfin database entities
  - Testing showed 2900 lookups with 0 images returned
  - **Impact:** Episode fallback chain skips TVDb episode images, uses Xtream → TVDb series poster instead
  - **Future:** See [TODO.md](./TODO.md) for workaround options (direct TVDb API, upstream PR)
  - **Files:** `Service/SeriesCacheService.cs` (lines 397-402 — call removed, method retained)

### Technical Details

**Metadata language injection:**
```csharp
// In Plugin constructor:
public Plugin(..., IServerConfigurationManager serverConfigManager, ...)

// In SeriesCacheService queries:
string? lang = _serverConfigManager?.Configuration?.PreferredMetadataLanguage;
SearchInfo = new() { MetadataLanguage = lang ?? string.Empty, ... }
```

**Season fallback chain:**
```csharp
string? cover = season?.Cover;  // Xtream season cover
cover ??= Plugin.Instance.SeriesCacheService.GetCachedTmdbImageUrl(seriesId);  // TVDb series poster
cover ??= series.Info.Cover;  // Xtream series cover
```

**Episode fallback chain:**
```csharp
string? cover = Plugin.Instance.SeriesCacheService.GetCachedEpisodeImageUrl(seriesId, season, episode);  // TVDb episode (disabled)
cover ??= episode.Info?.MovieImage;  // Xtream episode
cover ??= season?.Cover;  // Season cover
cover ??= Plugin.Instance.SeriesCacheService.GetCachedTmdbImageUrl(seriesId);  // TVDb series poster
cover ??= serie.Cover;  // Xtream series cover
```

---

## v0.9.12.0 (2026-01-28)

### Fixed — Cache Invalidation Hardening
- **TVDb settings in cache hash**: `UseTvdbForSeriesMetadata` and `TvdbTitleOverrides` are now included in `GetCacheRelevantHash()`
  - **Impact:** Changing title overrides or toggling TVDb now correctly invalidates cache and triggers re-fetch
  - **Before:** Changing overrides required manually clearing cache for changes to take effect
  - **After:** Saving settings with changed TVDb options automatically invalidates and re-fetches
  - **Files:** `Configuration/PluginConfiguration.cs` (line 186)

- **Cancel running refresh on config save**: `Plugin.UpdateConfiguration()` now calls `SeriesCacheService.CancelRefresh()` before starting new refresh
  - **Impact:** Override changes take effect immediately instead of waiting for current refresh to finish
  - **Files:** `Plugin.cs` (line 224)

- **CTS disposal race condition**: Atomic swap pattern for `_refreshCancellationTokenSource`
  - **Impact:** Prevents `ObjectDisposedException` when cancel and refresh overlap
  - **Files:** `Service/SeriesCacheService.cs` (lines 121-123)

### Technical Details

**GetCacheRelevantHash() update:**
```csharp
public int GetCacheRelevantHash()
{
    int hash = HashCode.Combine(BaseUrl, Username, Password, FlattenSeriesView);
    hash = HashCode.Combine(hash, UseTvdbForSeriesMetadata, TvdbTitleOverrides);  // NEW
    // ... series selections ...
    return hash;
}
```

**Cancel-on-save pattern:**
```csharp
// In Plugin.UpdateConfiguration():
SeriesCacheService.CancelRefresh();
_ = Task.Run(async () =>
{
    await Task.Delay(500).ConfigureAwait(false);  // Allow cancellation to propagate
    await SeriesCacheService.RefreshCacheAsync().ConfigureAwait(false);
});
```

**CTS atomic swap:**
```csharp
// In RefreshCacheAsync():
var oldCts = _refreshCancellationTokenSource;
_refreshCancellationTokenSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
oldCts?.Dispose();
```

---

## v0.9.11.0 (2026-01-28)

### Changed — Title Override Map (Replaces Language Booster)
- **NEW:** Title Override Map — map series titles directly to TVDb IDs
  - Format: `SeriesTitle=TVDbID` (one per line)
  - Case-insensitive matching against cleaned series names
  - Direct TVDb ID lookup bypasses search ambiguity
  - Falls back to name search if override lookup fails
  - **Files:** `Service/SeriesCacheService.cs` (`ParseTitleOverrides`, `LookupByTvdbIdAsync`)

- **NEW:** Configuration UI for overrides
  - Textarea in Series settings for entering mappings
  - Show/hide based on TVDb toggle state
  - **Files:** `Configuration/Web/XtreamSeries.html`, `Configuration/Web/XtreamSeries.js`

- **NEW:** `TvdbTitleOverrides` configuration property
  - **Files:** `Configuration/PluginConfiguration.cs`

- **REMOVED:** Language Matching Booster system
  - Removed 10 language JSON files
  - Removed language preset UI (dropdown selector)
  - Removed word translation tables
  - Removed article/and substitution logic
  - Removed `/Xtream/Languages` API endpoints
  - **Rationale:** Over-engineered for the problem. Simple overrides handle the 5-10 edge cases.

- **KEPT:** Name-based TVDb search for series without overrides
- **KEPT:** Language indicator stripping (e.g., `(NL Gesproken)` removed before search)

### Technical Details

**ParseTitleOverrides:**
```csharp
// Input: "Show A=123\nShow B=456"
// Output: { "Show A": "123", "Show B": "456" }
private static Dictionary<string, string> ParseTitleOverrides(string config)
```

**LookupByTvdbIdAsync:**
```csharp
// Uses ProviderIds to look up by TVDb ID directly
SearchInfo = new()
{
    Name = cleanName,
    ProviderIds = new Dictionary<string, string>
    {
        { MetadataProvider.Tvdb.ToString(), tvdbId }
    }
}
```

---

## v0.9.10.0 (2026-01-28)

### Added — Initial TVDb Integration (Language Matching Booster)
- **NEW:** TVDb artwork injection during cache refresh
  - Searches TVDb by series name via `IProviderManager`
  - Caches image URLs in `IMemoryCache`
  - Serves TVDb images instead of Xtream covers
  - **Files:** `Service/SeriesCacheService.cs` (`LookupAndCacheTmdbImageAsync`, `GetCachedTmdbImageUrl`, `GenerateSearchTerms`)

- **NEW:** Language indicator stripping before TVDb search
  - Strips `(NL Gesproken)`, `(DE)`, `(FR)`, `(Dutch)`, `(German)`, `(French)`, etc.
  - Generates fallback search terms without language indicators
  - **Files:** `Service/SeriesCacheService.cs` (`GenerateSearchTerms`)

- **NEW:** Placeholder image filtering
  - Skips TVDb results with `missing/series` or `missing/movie` in URL
  - Only caches results with valid artwork

- **NEW:** Fallback chain: TVDb image → Xtream cover
  - **Files:** `SeriesChannel.cs` (`CreateChannelItemInfo`)

- **NEW:** `UseTvdbForSeriesMetadata` configuration toggle
  - **Files:** `Configuration/PluginConfiguration.cs`

- **NEW:** Language Booster system (later removed in v0.9.11.0)
  - 10 language JSON preset files
  - Word translation tables
  - Article and conjunction substitution
  - UI language preset selector

### Technical Details

**Search flow:**
```
ParseName(seriesName) → cleanName
GenerateSearchTerms(cleanName) → [original, language-stripped]
For each term:
    IProviderManager.GetRemoteSearchResults("TheTVDB", term)
    Filter out missing/placeholder images
    Cache first valid image URL
```

**Image consumption in SeriesChannel:**
```csharp
string? imageUrl = Plugin.Instance.SeriesCacheService.GetCachedTmdbImageUrl(series.SeriesId);
imageUrl ??= series.Cover;  // Fallback to Xtream
```

---

## Architecture Evolution

### Phase 1: No Artwork Override (Original Plugin)
```
Series.Cover → ImageUrl
```
Problem: Xtream providers often block image access

### Phase 2: TVDb Integration with Language Booster (v0.9.10.0)
```
TVDb search (with language presets, word translation) → cache URL
TVDb image → Xtream cover fallback
```
Problem: Over-engineered language matching system

### Phase 3: Simplified Title Overrides (v0.9.11.0)
```
Title overrides → TVDb ID lookup → TVDb name search → Xtream cover
```
Benefit: Simple, maintainable, handles edge cases with manual mapping

### Phase 4: Hardened Cache Invalidation (v0.9.12.0)
```
TVDb settings in cache hash → proper invalidation on override changes
Cancel-on-save → immediate effect of setting changes
```
Benefit: Reliable cache behavior when changing TVDb settings

---

## Breaking Changes

**v0.9.11.0:**
- Removed Language Booster UI and API endpoints
- Users who configured language presets need to switch to title overrides
- Language indicator stripping still works automatically (no user action needed)

**v0.9.10.0 and v0.9.12.0:**
- None

---

## Performance Impact

| Version | Cache Refresh Impact | Notes |
|---------|---------------------|-------|
| v0.9.10.0 | +2-5 min | TVDb lookups (sequential) |
| v0.9.11.0 | +2-5 min | Same (simplified logic, same performance) |
| v0.9.12.0 | No change | Hardening only, no new lookups |

---

## References

- [REQUIREMENTS.md](./REQUIREMENTS.md) - Feature requirements
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Design decisions
- [IMPLEMENTATION.md](./IMPLEMENTATION.md) - Code changes
- [TEST_PLAN.md](./TEST_PLAN.md) - Test cases
