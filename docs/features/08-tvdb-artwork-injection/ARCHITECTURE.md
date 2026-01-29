# TVDb Artwork Injection - Architecture

## Document Info
- **Status:** Implemented
- **Version:** 0.9.11.0 (initial), 0.9.12.0 (hardened)
- **Last Updated:** 2026-01-28
- **Related:** [REQUIREMENTS.md](./REQUIREMENTS.md), [IMPLEMENTATION.md](./IMPLEMENTATION.md)

---

## Overview

The TVDb Artwork Injection feature extends the eager caching pipeline (Feature 04) to look up series artwork from TVDb. After all series data is cached from the Xtream API, a second pass iterates through every series, searches TVDb by name, and caches the image URL. When Jellyfin later requests channel items, the cached TVDb image is served instead of the Xtream cover.

---

## TVDb Lookup Pipeline

The lookup runs as the final phase of `RefreshCacheAsync()`, after all series/episodes are cached:

```
RefreshCacheAsync()
├── Phase 1: Fetch categories from Xtream API
├── Phase 2: Fetch series lists per category
├── Phase 3: Parallel fetch of seasons/episodes per series
├── Phase 4: TVDb artwork lookup (this feature)     ← NEW
│   ├── Parse title overrides once
│   ├── For each series:
│   │   ├── ParseName(seriesName) → cleanName
│   │   ├── Check title overrides map
│   │   │   ├── HIT: LookupByTvdbIdAsync(tvdbId)
│   │   │   │   ├── Found image → cache and return
│   │   │   │   └── No image → fall through to name search
│   │   │   └── MISS: continue to name search
│   │   ├── GenerateSearchTerms(cleanName)
│   │   │   ├── Term 1: original cleaned name
│   │   │   └── Term 2: language-stripped variant (if different)
│   │   ├── For each search term:
│   │   │   ├── Search TVDb via IProviderManager
│   │   │   ├── Find first result with valid image
│   │   │   └── Cache image URL if found
│   │   └── No match → log warning, no cached image
│   └── Log summary: N found, M not found
└── Phase 5: Eager populate Jellyfin database
```

---

## Integration with Cache Refresh Flow

### Position in Pipeline

TVDb lookup runs **after** all series data is cached (Phase 3) and **before** Jellyfin database population (Phase 5). This ensures:

1. Series names are available for lookup (from cached series lists)
2. Image URLs are cached before Jellyfin requests channel items
3. The `CreateChannelItemInfo()` method can read the cached image during population

### Cache Entry Lifecycle

```
Cache Refresh Start
    ↓
SeriesStreamInfo cached with key: {prefix}seriesinfo_{seriesId}
    ↓
TVDb image cached with key: {prefix}tmdb_image_{seriesId}
    ↓
Jellyfin population calls GetChannelItems()
    ↓
CreateChannelItemInfo(series) reads:
  1. GetCachedTmdbImageUrl(series.SeriesId) → TVDb image URL (or null)
  2. series.Cover → Xtream cover URL (fallback)
    ↓
Returns ChannelItemInfo with ImageUrl set
```

---

## Title Override System

### Parsing (`ParseTitleOverrides`)

The override configuration is a multi-line string parsed at the start of TVDb lookup:

```
Input:
"Knabbel en Babbel: Park Life=403215\nSome Show=123456"

Output (Dictionary<string, string>):
{
  "Knabbel en Babbel: Park Life" → "403215",
  "Some Show" → "123456"
}
```

**Parsing rules:**
- Split by newline (`\n`)
- For each line, find first `=` character
- Key = text before `=` (trimmed)
- Value = text after `=` (trimmed)
- Empty keys, empty values, and lines without `=` are skipped
- Dictionary uses `StringComparer.OrdinalIgnoreCase` (case-insensitive matching)

### Override Lookup Flow

```
cleanName = ParseName(series.Name).Title
    ↓
titleOverrides.TryGetValue(cleanName, out tvdbId)
    ↓
YES: LookupByTvdbIdAsync(cleanName, tvdbId)
  ├── Build query with ProviderIds = { "Tvdb": tvdbId }
  ├── Search TheTVDB provider
  ├── Find first result with valid image
  ├── HIT → cache URL, return
  └── MISS → log warning, fall through to name search
    ↓
NO: Continue to GenerateSearchTerms → name-based search
```

### Why Override Key is the Clean Name

The override map key is matched against the **cleaned** name (after `ParseName()` strips tags). This means:
- User sees "Knabbel en Babbel: Park Life" in the UI
- The raw name might be `[TAG]Knabbel en Babbel: Park Life[/TAG]`
- After `ParseName()`: "Knabbel en Babbel: Park Life"
- The override matches against this cleaned version

---

## Search Term Generation

`GenerateSearchTerms(name)` produces 1-2 search terms for TVDb:

```
Input: "The Flash (NL Gesproken)"

Term 1: "The Flash (NL Gesproken)"     ← original cleaned name
Term 2: "The Flash"                     ← language indicator stripped

Input: "Breaking Bad"

Term 1: "Breaking Bad"                  ← original (no language indicator)
(no Term 2 — stripping produced same result)
```

**Language indicator regex:**
```regex
\s*\([^)]*(?:Gesproken|Dubbed|Subbed|NL|DE|FR|Dutch|German|French|Nederlands|Deutsch)[^)]*\)\s*
```

This matches parenthetical expressions containing language keywords. The result is deduplicated (if stripping produces the same string, only one term is returned).

---

## TVDb Search via IProviderManager

The plugin uses Jellyfin's built-in provider infrastructure rather than calling the TVDb API directly:

```csharp
RemoteSearchQuery<SeriesInfo> query = new()
{
    SearchInfo = new() { Name = searchTerm },
    SearchProviderName = "TheTVDB",
};

IEnumerable<RemoteSearchResult> results = await _providerManager
    .GetRemoteSearchResults<Series, SeriesInfo>(query, cancellationToken);
```

**Advantages:**
- No external API keys needed (Jellyfin handles TVDb authentication)
- Reuses Jellyfin's HTTP client and caching
- Compatible with any Jellyfin version that ships the TVDb provider
- Results include `ImageUrl` for the series poster

**Result filtering:**
```csharp
RemoteSearchResult? resultWithImage = results.FirstOrDefault(r =>
    !string.IsNullOrEmpty(r.ImageUrl) &&
    !r.ImageUrl.Contains("missing/series", StringComparison.OrdinalIgnoreCase) &&
    !r.ImageUrl.Contains("missing/movie", StringComparison.OrdinalIgnoreCase));
```

This skips TVDb placeholder images that indicate no artwork is available.

### Direct ID Lookup

For title overrides, the query includes the TVDb ID in `ProviderIds`:

```csharp
SearchInfo = new()
{
    Name = cleanName,
    ProviderIds = new Dictionary<string, string>
    {
        { MetadataProvider.Tvdb.ToString(), tvdbId }
    }
}
```

This tells the TVDb provider to look up the specific series by ID rather than searching by name, eliminating ambiguity.

---

## Cache Key Format

TVDb image URLs are stored in `IMemoryCache` using the same prefix as other cache entries:

```
{CachePrefix}tmdb_image_{seriesId}

Where CachePrefix = series_cache_{CacheDataVersion}_v{CacheVersion}_

Example:
series_cache_abc123_v0_tmdb_image_19259
```

**Note:** The cache key uses `tmdb_image_` (historical naming from when TMDB was considered). The data stored is actually a TVDb image URL. This is a naming inconsistency that doesn't affect functionality.

**Cache options:** Same 24-hour `AbsoluteExpirationRelativeToNow` as all other cache entries.

---

## Fallback Chain

When `CreateChannelItemInfo(Series series)` is called in `SeriesChannel.cs`:

```csharp
// 1. Try cached TVDb image
string? imageUrl = Plugin.Instance.SeriesCacheService.GetCachedTmdbImageUrl(series.SeriesId);

// 2. Fall back to Xtream cover
imageUrl ??= series.Cover;

// 3. Set on channel item
return new ChannelItemInfo()
{
    ImageUrl = imageUrl,
    // ...
};
```

**Fallback scenarios:**
| Scenario | TVDb Cache | Result |
|----------|-----------|--------|
| TVDb match found | Image URL | TVDb image displayed |
| TVDb no match | null | Xtream cover displayed |
| TVDb disabled | null (not cached) | Xtream cover displayed |
| Both null | null | No image (Jellyfin default) |

---

## Cache Invalidation

### TVDb Settings in Cache Hash

`GetCacheRelevantHash()` in `PluginConfiguration.cs` includes TVDb settings:

```csharp
public int GetCacheRelevantHash()
{
    int hash = HashCode.Combine(BaseUrl, Username, Password, FlattenSeriesView);
    hash = HashCode.Combine(hash, UseTvdbForSeriesMetadata, TvdbTitleOverrides);
    // ... series selections ...
    return hash;
}
```

**When cache is invalidated:**
- `UseTvdbForSeriesMetadata` toggled (on→off or off→on)
- `TvdbTitleOverrides` text changed (added, removed, or modified a mapping)
- Any other cache-relevant setting changed (credentials, categories, etc.)

**Effect:** The `CacheDataVersion` changes, making all old cache keys inaccessible. The next refresh starts fresh with the new settings.

### Cancel-on-Save Behavior

When configuration is saved (`Plugin.UpdateConfiguration()`):

```csharp
// Cancel any running refresh so the new one can start with updated settings
SeriesCacheService.CancelRefresh();

_ = Task.Run(async () =>
{
    await Task.Delay(500).ConfigureAwait(false);  // Allow cancellation to propagate
    await SeriesCacheService.RefreshCacheAsync().ConfigureAwait(false);
});
```

This ensures that changing title overrides takes effect immediately rather than waiting for the current refresh to complete.

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    Configuration                         │
│  UseTvdbForSeriesMetadata: true                         │
│  TvdbTitleOverrides: "Show A=123\nShow B=456"           │
└───────────────┬─────────────────────────────────────────┘
                │
                ↓
┌─────────────────────────────────────────────────────────┐
│              SeriesCacheService.RefreshCacheAsync()       │
│                                                          │
│  1. Parse overrides → { "Show A": "123", "Show B": "456" } │
│  2. For each series:                                     │
│     series.Name = "[TAG] Show A (NL Gesproken)"         │
│     cleanName = ParseName() → "Show A (NL Gesproken)"   │
│     Check overrides("Show A (NL Gesproken)") → MISS     │
│     Search terms: ["Show A (NL Gesproken)", "Show A"]    │
│     TVDb search "Show A (NL Gesproken)" → no result     │
│     TVDb search "Show A" → found! image URL              │
│     Cache: tmdb_image_12345 = "https://tvdb.../img.jpg" │
└───────────────┬─────────────────────────────────────────┘
                │
                ↓
┌─────────────────────────────────────────────────────────┐
│              SeriesChannel.CreateChannelItemInfo()        │
│                                                          │
│  imageUrl = GetCachedTmdbImageUrl(12345)                 │
│           = "https://tvdb.../img.jpg"                    │
│  imageUrl ??= series.Cover  (not needed, TVDb found)     │
│  return ChannelItemInfo { ImageUrl = imageUrl }          │
└─────────────────────────────────────────────────────────┘
```

---

## Design Decisions

### D-1: Sequential TVDb Lookups (Not Parallel)

**Decision:** TVDb lookups run sequentially, one series at a time.

**Rationale:**
- TVDb API has rate limits
- Jellyfin's provider manager may not be thread-safe for concurrent searches
- Adding 2-5 minutes to a 5-15 minute cache refresh is acceptable
- Simpler error handling and logging

### D-2: Title Override Map Instead of Language Presets

**Decision:** Simple `Title=TVDbID` text format instead of language-specific presets with word translation tables.

**Rationale:**
- v0.9.10.0 initially implemented language presets (10 JSON files, word translation, article substitution)
- This was over-engineered — most series match fine with name search + language stripping
- Only a handful of series need manual mapping
- Simple text format is easy to understand, edit, and maintain
- No language JSON files to ship and maintain

**History:**
- v0.9.10.0: Language Matching Booster (presets, translations, complex regex)
- v0.9.11.0: Replaced with Title Override Map (simple `Title=TVDbID`)

### D-3: Using IProviderManager Instead of Direct TVDb API

**Decision:** Use Jellyfin's built-in `IProviderManager` for TVDb searches.

**Rationale:**
- No external API keys needed
- Leverages Jellyfin's existing TVDb authentication
- Future-proof (Jellyfin handles API changes)
- One less external dependency to manage

### D-4: Cache Key Naming (tmdb_image_ prefix)

**Decision:** Keep the `tmdb_image_` cache key prefix despite using TVDb.

**Rationale:**
- Historical: initially planned to use TMDB, later switched to TVDb
- Changing the prefix would invalidate existing caches unnecessarily
- The key prefix is internal and not user-visible
- Functional correctness is not affected

---

## Component Diagram

```
┌──────────────────────────────────────────────────────┐
│                  Plugin.cs                            │
│  - Creates SeriesCacheService with IProviderManager   │
│  - UpdateConfiguration() → cancel + re-refresh        │
└──────────┬───────────────────────────────────────────┘
           │ owns
           ↓
┌──────────────────────────────────────────────────────┐
│            SeriesCacheService                          │
│                                                       │
│  RefreshCacheAsync()                                  │
│  ├── ... (existing cache phases) ...                  │
│  ├── LookupAndCacheTmdbImageAsync()  ← per series    │
│  │   ├── ParseTitleOverrides()       ← once           │
│  │   ├── LookupByTvdbIdAsync()       ← for overrides │
│  │   └── GenerateSearchTerms()       ← for search    │
│  └── PopulateJellyfinDatabaseAsync()                 │
│                                                       │
│  GetCachedTmdbImageUrl()             ← read cache    │
└──────────┬───────────────────────────────────────────┘
           │ uses
           ↓
┌──────────────────────────────────────────────────────┐
│            IProviderManager (Jellyfin)                 │
│  GetRemoteSearchResults<Series, SeriesInfo>()         │
│  - Routes to TheTVDB provider                         │
│  - Returns RemoteSearchResult with ImageUrl           │
└──────────────────────────────────────────────────────┘
```

---

## Related Documents

- [REQUIREMENTS.md](./REQUIREMENTS.md) - Functional and non-functional requirements
- [IMPLEMENTATION.md](./IMPLEMENTATION.md) - Code changes and file modifications
- [TEST_PLAN.md](./TEST_PLAN.md) - Test suites for validation
- [CHANGELOG.md](./CHANGELOG.md) - Version history
- [Feature 04: Eager Caching](../04-eager-caching/ARCHITECTURE.md) - Cache infrastructure this extends
