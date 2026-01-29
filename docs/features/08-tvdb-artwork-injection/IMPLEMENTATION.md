# TVDb Artwork Injection - Implementation Details

## Document Info
- **Status:** Implemented
- **Version:** 0.9.11.0 (initial), 0.9.12.0 (hardened)
- **Last Updated:** 2026-01-28
- **Related:** [REQUIREMENTS.md](./REQUIREMENTS.md), [ARCHITECTURE.md](./ARCHITECTURE.md)

---

## Implementation Approach

The feature was implemented in three iterations:

1. **v0.9.10.0 (Language Matching Booster):** Initial TVDb integration with language presets, word translation tables, and complex matching logic. Over-engineered.
2. **v0.9.11.0 (Title Override Map):** Simplified to name-based search + manual `Title=TVDbID` overrides. Removed all language preset infrastructure.
3. **v0.9.12.0 (Hardening):** Added TVDb settings to cache hash for proper invalidation. Cancel-on-save behavior.

---

## Files Modified

### 1. `Service/SeriesCacheService.cs`

The main implementation file. All TVDb-related methods are in this class.

#### Constructor Change

Added `IProviderManager? providerManager` parameter:

```csharp
public SeriesCacheService(
    StreamService streamService,
    IMemoryCache memoryCache,
    FailureTrackingService failureTrackingService,
    ILogger<SeriesCacheService>? logger = null,
    IProviderManager? providerManager = null)  // ← NEW
```

The provider manager is injected from `Plugin.cs` and used for TVDb searches.

#### `RefreshCacheAsync()` — TVDb Lookup Phase (lines 343-390)

After parallel series processing completes, a new phase runs TVDb lookups:

```csharp
// Fetch TVDb images for series if enabled
bool useTvdb = Plugin.Instance?.Configuration.UseTvdbForSeriesMetadata ?? true;
if (useTvdb && _providerManager != null)
{
    _logger?.LogInformation("Looking up TVDb metadata for {Count} series...", totalSeries);
    _currentStatus = "Fetching TVDb images...";

    // Parse title overrides once before the lookup loop
    Dictionary<string, string> titleOverrides = ParseTitleOverrides(
        Plugin.Instance?.Configuration.TvdbTitleOverrides ?? string.Empty);

    if (titleOverrides.Count > 0)
    {
        _logger?.LogInformation("Loaded {Count} TVDb title overrides", titleOverrides.Count);
    }

    int tmdbFound = 0;
    int tmdbNotFound = 0;

    foreach (var kvp in seriesListsByCategory)
    {
        foreach (var series in kvp.Value)
        {
            _refreshCancellationTokenSource.Token.ThrowIfCancellationRequested();

            string? tmdbUrl = await LookupAndCacheTmdbImageAsync(
                series.SeriesId,
                series.Name,
                titleOverrides,
                cacheOptions,
                _refreshCancellationTokenSource.Token).ConfigureAwait(false);

            if (tmdbUrl != null)
                tmdbFound++;
            else
                tmdbNotFound++;
        }
    }

    _logger?.LogInformation(
        "TVDb lookup completed: {Found} found, {NotFound} not found",
        tmdbFound, tmdbNotFound);
}
```

**Key points:**
- Runs sequentially (not parallel) to respect TVDb rate limits
- Uses the already-fetched `seriesListsByCategory` dictionary (no extra API calls)
- Respects cancellation token for config save interruption
- Title overrides are parsed once, not per-series

#### `LookupAndCacheTmdbImageAsync()` (lines 592-673)

Core lookup method for a single series:

```csharp
private async Task<string?> LookupAndCacheTmdbImageAsync(
    int seriesId,
    string seriesName,
    Dictionary<string, string> titleOverrides,
    MemoryCacheEntryOptions cacheOptions,
    CancellationToken cancellationToken)
{
    if (_providerManager == null) return null;

    try
    {
        // Parse the name to remove tags
        string cleanName = StreamService.ParseName(seriesName).Title;
        if (string.IsNullOrWhiteSpace(cleanName)) return null;

        // Check title overrides first for direct TVDb ID lookup
        if (titleOverrides.TryGetValue(cleanName, out string? tvdbId))
        {
            string? overrideResult = await LookupByTvdbIdAsync(cleanName, tvdbId, cancellationToken);
            if (overrideResult != null)
            {
                _memoryCache.Set($"{CachePrefix}tmdb_image_{seriesId}", overrideResult, cacheOptions);
                return overrideResult;
            }
            // Override failed — fall through to name search
        }

        // Fall back to name-based search with progressively cleaned search terms
        string[] searchTerms = GenerateSearchTerms(cleanName);

        foreach (string searchTerm in searchTerms)
        {
            if (string.IsNullOrWhiteSpace(searchTerm)) continue;

            RemoteSearchQuery<SeriesInfo> query = new()
            {
                SearchInfo = new() { Name = searchTerm },
                SearchProviderName = "TheTVDB",
            };

            IEnumerable<RemoteSearchResult> results = await _providerManager
                .GetRemoteSearchResults<Series, SeriesInfo>(query, cancellationToken);

            RemoteSearchResult? resultWithImage = results.FirstOrDefault(r =>
                !string.IsNullOrEmpty(r.ImageUrl) &&
                !r.ImageUrl.Contains("missing/series", StringComparison.OrdinalIgnoreCase) &&
                !r.ImageUrl.Contains("missing/movie", StringComparison.OrdinalIgnoreCase));

            if (resultWithImage?.ImageUrl != null)
            {
                _memoryCache.Set($"{CachePrefix}tmdb_image_{seriesId}", resultWithImage.ImageUrl, cacheOptions);
                return resultWithImage.ImageUrl;
            }
        }

        _logger?.LogWarning("TVDb search found no image for series {SeriesId} ({Name})", seriesId, cleanName);
    }
    catch (Exception ex)
    {
        _logger?.LogWarning(ex, "Failed to lookup TVDb image for series {SeriesId} ({Name})", seriesId, seriesName);
    }

    return null;
}
```

#### `LookupByTvdbIdAsync()` (lines 682-715)

Direct TVDb ID lookup for title overrides:

```csharp
private async Task<string?> LookupByTvdbIdAsync(
    string cleanName,
    string tvdbId,
    CancellationToken cancellationToken)
{
    if (_providerManager == null) return null;

    RemoteSearchQuery<SeriesInfo> query = new()
    {
        SearchInfo = new()
        {
            Name = cleanName,
            ProviderIds = new Dictionary<string, string>
            {
                { MetadataProvider.Tvdb.ToString(), tvdbId }
            }
        },
        SearchProviderName = "TheTVDB",
    };

    IEnumerable<RemoteSearchResult> results = await _providerManager
        .GetRemoteSearchResults<Series, SeriesInfo>(query, cancellationToken);

    RemoteSearchResult? resultWithImage = results.FirstOrDefault(r =>
        !string.IsNullOrEmpty(r.ImageUrl) &&
        !r.ImageUrl.Contains("missing/series", StringComparison.OrdinalIgnoreCase) &&
        !r.ImageUrl.Contains("missing/movie", StringComparison.OrdinalIgnoreCase));

    return resultWithImage?.ImageUrl;
}
```

#### `GenerateSearchTerms()` (lines 723-743)

Produces search term variants for TVDb:

```csharp
private static string[] GenerateSearchTerms(string name)
{
    List<string> terms = new();

    // 1. Add original name first
    terms.Add(name);

    // 2. Remove language indicators
    string withoutLang = Regex.Replace(
        name,
        @"\s*\([^)]*(?:Gesproken|Dubbed|Subbed|NL|DE|FR|Dutch|German|French|Nederlands|Deutsch)[^)]*\)\s*",
        string.Empty,
        RegexOptions.IgnoreCase).Trim();

    if (!string.Equals(withoutLang, name, StringComparison.OrdinalIgnoreCase)
        && !string.IsNullOrWhiteSpace(withoutLang))
    {
        terms.Add(withoutLang);
    }

    return terms.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
}
```

#### `ParseTitleOverrides()` (lines 749-773)

Parses the configuration textarea into a dictionary:

```csharp
private static Dictionary<string, string> ParseTitleOverrides(string config)
{
    var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

    if (string.IsNullOrWhiteSpace(config)) return result;

    foreach (string line in config.Split('\n',
        StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
    {
        int equalsIndex = line.IndexOf('=', StringComparison.Ordinal);
        if (equalsIndex > 0 && equalsIndex < line.Length - 1)
        {
            string key = line[..equalsIndex].Trim();
            string value = line[(equalsIndex + 1)..].Trim();
            if (!string.IsNullOrEmpty(key) && !string.IsNullOrEmpty(value))
            {
                result[key] = value;
            }
        }
    }

    return result;
}
```

#### `GetCachedTmdbImageUrl()` (lines 562-580)

Cache read method consumed by `SeriesChannel`:

```csharp
public string? GetCachedTmdbImageUrl(int seriesId)
{
    try
    {
        string cacheKey = $"{CachePrefix}tmdb_image_{seriesId}";
        if (_memoryCache.TryGetValue(cacheKey, out string? imageUrl) && imageUrl != null)
        {
            return imageUrl;
        }

        _logger?.LogWarning("No cached TVDb image found for series {SeriesId}", seriesId);
        return null;
    }
    catch (Exception ex)
    {
        _logger?.LogWarning(ex, "Error retrieving cached TVDb image for series {SeriesId}", seriesId);
        return null;
    }
}
```

---

### 2. `SeriesChannel.cs` — Image Consumption (line 135-157)

`CreateChannelItemInfo(Series series)` now reads the cached TVDb image:

```csharp
private ChannelItemInfo CreateChannelItemInfo(Series series)
{
    ParsedName parsedName = StreamService.ParseName(series.Name);

    // Use cached TVDb image if available, otherwise fall back to Xtream cover
    string? imageUrl = Plugin.Instance.SeriesCacheService.GetCachedTmdbImageUrl(series.SeriesId);
    imageUrl ??= series.Cover;

    return new ChannelItemInfo()
    {
        // ...
        ImageUrl = imageUrl,
        Name = parsedName.Title,
        // ...
    };
}
```

**Change:** Previously `ImageUrl = series.Cover` was hardcoded. Now it first checks the TVDb cache.

---

### 3. `Configuration/PluginConfiguration.cs` — Settings (lines 139-152)

Two new configuration properties:

```csharp
/// <summary>
/// Gets or sets a value indicating whether to use TVDb for series metadata and images.
/// Default is true.
/// </summary>
public bool UseTvdbForSeriesMetadata { get; set; } = true;

/// <summary>
/// Gets or sets title-to-TVDb-ID overrides for series that can't be found by name search.
/// Format: one mapping per line, "SeriesTitle=TVDbID".
/// </summary>
public string TvdbTitleOverrides { get; set; } = string.Empty;
```

#### `GetCacheRelevantHash()` — TVDb Settings Inclusion (line 186)

```csharp
public int GetCacheRelevantHash()
{
    int hash = HashCode.Combine(BaseUrl, Username, Password, FlattenSeriesView);
    hash = HashCode.Combine(hash, UseTvdbForSeriesMetadata, TvdbTitleOverrides);  // ← NEW
    // ... series selections ...
    return hash;
}
```

This ensures changing TVDb settings invalidates the cache and triggers a re-fetch.

---

### 4. `Configuration/Web/XtreamSeries.html` — TVDb Settings UI

A new settings section was added to the Series configuration page (not shown in full — embedded HTML resource).

**UI elements:**
- **Checkbox:** "Use TVDb for Series Artwork" (`#UseTvdbForSeriesMetadata`)
- **Textarea:** "Title Override Map" (`#TvdbTitleOverrides`)
  - Placeholder text explaining the format
  - Shows/hides based on checkbox state
- **Container:** `#TvdbOptionsContainer` wraps the textarea (toggleable)

---

### 5. `Configuration/Web/XtreamSeries.js` — TVDb Settings Logic (lines 27-73, 287-289)

**DOM element references:**

```javascript
const useTvdbForSeriesMetadata = view.querySelector("#UseTvdbForSeriesMetadata");
const tvdbOptionsContainer = view.querySelector("#TvdbOptionsContainer");
const tvdbTitleOverrides = view.querySelector("#TvdbTitleOverrides");
```

**Visibility toggle:**

```javascript
function updateTvdbOptionsVisibility() {
    tvdbOptionsContainer.style.display = useTvdbForSeriesMetadata.checked ? 'block' : 'none';
}

useTvdbForSeriesMetadata.addEventListener('change', updateTvdbOptionsVisibility);
```

**Load config:**

```javascript
getConfig.then((config) => {
    useTvdbForSeriesMetadata.checked = config.UseTvdbForSeriesMetadata !== false;
    tvdbTitleOverrides.value = config.TvdbTitleOverrides || '';
    updateTvdbOptionsVisibility();
});
```

**Save config:**

```javascript
config.UseTvdbForSeriesMetadata = useTvdbForSeriesMetadata.checked;
config.TvdbTitleOverrides = tvdbTitleOverrides.value;
```

---

### 6. `Plugin.cs` — Provider Manager Injection (lines 65-86)

Constructor now accepts and passes `IProviderManager`:

```csharp
public Plugin(
    // ... existing params ...
    IProviderManager providerManager,  // ← NEW
    ILogger<Plugin> logger,
    ILoggerFactory loggerFactory)
{
    // ...
    SeriesCacheService = new Service.SeriesCacheService(
        StreamService,
        memoryCache,
        failureTrackingService,
        loggerFactory.CreateLogger<Service.SeriesCacheService>(),
        providerManager);  // ← NEW
}
```

---

## Implementation Decisions

### D-1: Why `IProviderManager` Instead of Direct HTTP to TVDb

**Decision:** Use Jellyfin's built-in provider infrastructure.

**Rationale:**
- TVDb requires API authentication (subscriber key)
- Jellyfin's TVDb plugin handles this transparently
- No need to manage API keys, tokens, or rate limiting
- Future-proof: if Jellyfin changes TVDb integration, the plugin adapts automatically

### D-2: Why Sequential Lookups

**Decision:** TVDb lookups run one-at-a-time, not in parallel.

**Rationale:**
- TVDb has rate limits that parallel requests would hit
- The provider manager's thread safety for concurrent searches is not guaranteed
- 2-5 minutes additional time is acceptable (runs in background)
- Simpler error handling and progress tracking

### D-3: Why ParseName Before Override Check

**Decision:** Override keys match against cleaned names (after `ParseName()` strips tags).

**Rationale:**
- Users see cleaned names in the Jellyfin UI
- Users configure overrides based on what they see
- Raw Xtream names with `[TAG]` prefixes are not user-friendly
- Consistent with how series names are displayed throughout the plugin

### D-4: Why Case-Insensitive Override Matching

**Decision:** `StringComparer.OrdinalIgnoreCase` for the override dictionary.

**Rationale:**
- Users may not match exact capitalization when typing overrides
- "the flash=12345" and "The Flash=12345" should both work
- Reduces configuration errors

---

## Evolution History

### v0.9.10.0: Language Matching Booster (Removed)

The initial implementation was significantly more complex:

- **10 language JSON files** (English, Dutch, German, French, etc.) with word translation tables
- **Language preset system** in UI (dropdown to select language)
- **Word translation** ("and" → "en" for Dutch)
- **Article substitution** ("The" → "De/Het" for Dutch)
- **3 API endpoints** for language data
- **~500 lines** of language-specific matching code

This was removed in v0.9.11.0 because:
- Most series match fine with name search alone
- Language stripping (`(NL Gesproken)` → removed) handles most edge cases
- Only 5-10 series typically need manual mapping
- Simple `Title=TVDbID` override is easier to understand and maintain

### v0.9.11.0: Title Override Map (Current)

Simplified to:
- Name-based TVDb search (with language stripping)
- Manual `Title=TVDbID` overrides for edge cases
- Total: ~200 lines of new code vs ~500 lines removed

### v0.9.12.0: Hardening

Added:
- TVDb settings in `GetCacheRelevantHash()` — changing overrides invalidates cache
- Cancel-on-save — config save cancels running refresh and starts new one
- CTS atomic swap pattern — prevents disposal race conditions

---

## Logging

### TVDb Lookup Logging

```
[INF] Looking up TVDb metadata for 666 series...
[INF] Loaded 5 TVDb title overrides
[INF] Using TVDb title override for series 12345 (Show Name) → TVDb ID 403215
[INF] Cached TVDb image for series 12345 (Show Name) via override (TVDb ID 403215): https://...
[INF] Cached TVDb image for series 12346 (Other Show) using search term 'Other Show': https://...
[WRN] TVDb search found no image for series 12347 (Unknown Show) after trying: Unknown Show
[WRN] Failed to lookup TVDb image for series 12348 (Bad Show): Network error
[INF] TVDb lookup completed: 600 found, 66 not found
```

### Cache Read Logging

```
[WRN] No cached TVDb image found for series 12347 (key: series_cache_abc_v0_tmdb_image_12347)
```

---

## Related Commits

- `3c014eb` - v0.9.10.0: Language Matching Booster (initial TVDb integration)
- `c8fcc0f` - v0.9.11.0: Title Override Map (replaced Language Booster)
- v0.9.12.0 commits: TVDb settings in cache hash, cancel-on-save

---

## References

- [REQUIREMENTS.md](./REQUIREMENTS.md) - Feature requirements
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Design decisions and data flow
- [TEST_PLAN.md](./TEST_PLAN.md) - Test suites
- [CHANGELOG.md](./CHANGELOG.md) - Version history
- [Feature 04: Eager Caching](../04-eager-caching/IMPLEMENTATION.md) - Cache infrastructure
