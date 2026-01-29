# TVDb Artwork Injection - Requirements

## Document Info
- **Status:** Implemented
- **Version:** 0.9.11.0 (initial), 0.9.12.0 (hardened)
- **Last Updated:** 2026-01-28
- **Related:** [ARCHITECTURE.md](./ARCHITECTURE.md), [IMPLEMENTATION.md](./IMPLEMENTATION.md)

---

## Problem Statement

Xtream providers often block image access or serve low-quality artwork for series. Users see broken images or unappealing thumbnails in their Jellyfin library. The Xtream `cover` URL may return:
- HTTP 403 Forbidden (provider blocks direct image access)
- Low-resolution thumbnails
- Generic placeholder images
- Nothing at all (empty string)

This makes the series library look unprofessional and hard to browse visually.

---

## Solution

During cache refresh, look up each series on TVDb (via Jellyfin's built-in provider infrastructure) and cache the resulting image URLs. When Jellyfin requests channel items, serve the TVDb image instead of the Xtream cover. A manual title override system lets users map series that can't be found by name search directly to TVDb IDs.

---

## User Stories

### US-1: Automatic Artwork Replacement
**As a** Jellyfin user with an Xtream provider that blocks images,
**I want** series artwork to be automatically sourced from TVDb,
**So that** my library has proper, high-quality artwork without manual intervention.

### US-2: Manual Title Override
**As a** user with series that have non-English names or unusual titles,
**I want** to manually map a series title to a specific TVDb ID,
**So that** series that can't be found by name search still get correct artwork.

### US-3: Fallback to Xtream Cover
**As a** user with a provider that serves good artwork,
**I want** the original Xtream cover to be used when TVDb has no match,
**So that** no series loses its artwork due to the TVDb integration.

### US-4: Enable/Disable Toggle
**As an** administrator,
**I want** to enable or disable TVDb artwork injection,
**So that** I can control whether the feature runs during cache refresh.

---

## Functional Requirements

### FR-1: TVDb Lookup During Cache Refresh
- After series/episodes are cached, iterate through all series
- For each series, search TVDb using the cleaned series name
- Use Jellyfin's built-in `IProviderManager` for the search (no external API keys needed)
- Search provider: "TheTVDB"

### FR-2: Title Override Map
- Users can configure manual `SeriesTitle=TVDbID` mappings
- Format: one mapping per line in a textarea
- Override is checked **before** name-based search
- When an override exists, look up the series directly by TVDb ID
- If the override lookup fails, fall back to name-based search
- Configuration property: `TvdbTitleOverrides` (string)

### FR-3: Image URL Caching
- Cache TVDb image URLs in `IMemoryCache` alongside other series data
- Cache key format: `{CachePrefix}tmdb_image_{seriesId}`
- Same 24-hour expiration as other cache entries
- Cached during refresh, consumed during `GetChannelItems()` calls

### FR-4: Fallback Chain
Priority order for series artwork:
1. **TVDb override** (if title exists in override map, look up by TVDb ID)
2. **TVDb name search** (search TVDb by cleaned series name)
3. **TVDb language-stripped search** (strip language indicators, search again)
4. **Xtream cover** (original provider image URL)

### FR-5: Language Indicator Stripping
- Before searching TVDb, strip language indicators from series names
- Patterns removed: `(NL Gesproken)`, `(DE)`, `(FR)`, `(Dutch)`, `(German)`, `(French)`, `(Nederlands)`, `(Deutsch)`, `(Dubbed)`, `(Subbed)`
- The stripped variant is tried as a second search term if different from the original
- Regex: `\s*\([^)]*(?:Gesproken|Dubbed|Subbed|NL|DE|FR|Dutch|German|French|Nederlands|Deutsch)[^)]*\)\s*`

### FR-6: Configuration UI
- **TVDb Artwork toggle** (`UseTvdbForSeriesMetadata`): Enable/disable the feature
- **Title Override textarea** (`TvdbTitleOverrides`): Multi-line text area for manual mappings
- TVDb options section is shown/hidden based on toggle state
- Located in the Series settings page (`XtreamSeries.html`)

---

## Non-Functional Requirements

### NFR-1: Performance
- TVDb lookup adds approximately 2-5 minutes to cache refresh (depends on library size and network)
- Lookups are sequential (one at a time) to avoid overwhelming TVDb API
- No impact on browsing performance (images are served from cache)

### NFR-2: No External API Keys
- Uses Jellyfin's built-in `IProviderManager` which handles TVDb authentication
- Requires the Jellyfin TVDb metadata provider plugin to be installed (ships by default)
- No additional configuration beyond the plugin's own settings

### NFR-3: Cache Invalidation
- TVDb settings (`UseTvdbForSeriesMetadata`, `TvdbTitleOverrides`) are included in `GetCacheRelevantHash()`
- Changing TVDb settings triggers cache invalidation and re-fetching
- Toggling the feature off removes TVDb images from cache (next refresh won't look them up)

### NFR-4: Image Quality
- TVDb images are filtered to exclude placeholder/missing images
- Images containing "missing/series" or "missing/movie" in the URL are skipped
- Only results with valid, non-placeholder image URLs are cached

---

## Configuration Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `UseTvdbForSeriesMetadata` | bool | `true` | Enable TVDb artwork injection |
| `TvdbTitleOverrides` | string | `""` | Multi-line title-to-TVDb-ID mappings |

### Title Override Format
```
SeriesTitle=TVDbID
Another Series Name=123456
Knabbel en Babbel: Park Life=403215
```

- One mapping per line
- `=` separates title from TVDb ID
- Title is matched case-insensitively against the **cleaned** series name (after `ParseName()`)
- TVDb ID is the numeric ID from the TVDb URL (e.g., `https://thetvdb.com/series/show-name` → look up the series page for the numeric ID)
- Empty lines and lines without `=` are ignored

---

## Acceptance Criteria

- [ ] Series with TVDb matches display TVDb artwork instead of Xtream cover
- [ ] Series without TVDb matches still display Xtream cover (no broken images)
- [ ] Title overrides correctly map to specific TVDb series
- [ ] Language indicators are stripped before search
- [ ] Feature can be toggled on/off via settings
- [ ] Changing title overrides triggers cache re-fetch
- [ ] No external API keys required

---

## Dependencies

- **Jellyfin TVDb metadata provider** (installed by default)
- **Feature 04: Eager Caching** (TVDb lookup runs during cache refresh)
- **`ParseName()`** (title cleaning before TVDb search)

---

## References

- [ARCHITECTURE.md](./ARCHITECTURE.md) - TVDb lookup pipeline and integration design
- [IMPLEMENTATION.md](./IMPLEMENTATION.md) - Code changes and file list
- [TEST_PLAN.md](./TEST_PLAN.md) - Test suites for TVDb integration
- [Feature 04: Eager Caching](../04-eager-caching/REQUIREMENTS.md) - Cache infrastructure this feature extends
