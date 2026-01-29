# TVDb Artwork Injection - TODO

## Document Info
- **Status:** Active
- **Last Updated:** 2026-01-29
- **Related:** [REQUIREMENTS.md](./REQUIREMENTS.md), [ARCHITECTURE.md](./ARCHITECTURE.md)

---

## Outstanding Tasks

### 1. Per-Episode TVDb Images via Direct API

**Priority:** Medium
**Complexity:** High
**Status:** Not started

The standard Jellyfin provider API (`GetRemoteSearchResults<Episode, EpisodeInfo>`) does not return episode images because `TvdbEpisodeProvider.GetSearchResults()` does not populate `ImageUrl`. The image-fetching interface (`TvdbEpisodeImageProvider.GetImages()`) requires actual Jellyfin `Episode` entities in the database, which channel plugins don't have.

**Workaround:** Call the TVDb API v4 directly to fetch episode images.

**Implementation approach:**
1. Add `System.Net.Http.HttpClient` for direct TVDb API calls
2. Implement TVDb API v4 authentication (requires API key from thetvdb.com)
3. Query `GET /series/{id}/episodes` to get episode TVDb IDs
4. Query `GET /episodes/{id}` to get episode image URL
5. Cache episode images alongside series images

**API endpoints:**
- Base: `https://api4.thetvdb.com/v4`
- Auth: `POST /login` with `{"apikey": "..."}`
- Episodes: `GET /series/{id}/episodes/{season-type}`
- Episode detail: `GET /episodes/{id}`

**Considerations:**
- Requires separate TVDb API key (free registration at thetvdb.com)
- New configuration property for API key
- Rate limiting (TVDb allows 100 requests/minute)
- May duplicate some functionality already in TVDb plugin

**Files to modify:**
- `Configuration/PluginConfiguration.cs` — add `TvdbApiKey` property
- `Configuration/Web/XtreamSeries.html/js` — add API key input
- `Service/SeriesCacheService.cs` — implement direct TVDb API client

---

### 2. TVDb Plugin PR: Populate ImageUrl in Episode Search Results

**Priority:** High (if accepted, solves the problem cleanly)
**Complexity:** Low (for the PR itself)
**Status:** Not started

Submit a pull request to [jellyfin/jellyfin-plugin-tvdb](https://github.com/jellyfin/jellyfin-plugin-tvdb) requesting that `TvdbEpisodeProvider.GetSearchResults()` populate `ImageUrl` on `RemoteSearchResult`, similar to how `TvdbSeriesProvider.GetSearchResults()` does.

**Current behavior:**
```csharp
// TvdbEpisodeProvider.GetSearchResults() returns:
new RemoteSearchResult
{
    IndexNumber = episode.Number,
    Name = episode.Name,
    ParentIndexNumber = episode.SeasonNumber,
    PremiereDate = episode.Aired,
    // ImageUrl is NOT set
}
```

**Requested behavior:**
```csharp
new RemoteSearchResult
{
    IndexNumber = episode.Number,
    Name = episode.Name,
    ParentIndexNumber = episode.SeasonNumber,
    PremiereDate = episode.Aired,
    ImageUrl = episode.Image,  // ADD THIS
}
```

**Steps:**
1. Fork `jellyfin/jellyfin-plugin-tvdb`
2. Modify `Providers/TvdbEpisodeProvider.cs` `GetSearchResults()` method
3. Add `ImageUrl = result.Image` to the `RemoteSearchResult` construction
4. Test with a Jellyfin instance
5. Submit PR with rationale: enables channel plugins to fetch episode thumbnails

**Rationale for PR:**
- Series search results already include `ImageUrl`
- Episode image data is available from TVDb API response
- Only requires adding one line to populate the property
- Enables new use cases (channel plugins, custom metadata tools)

**If accepted:** Remove the direct API workaround code and re-enable `LookupAndCacheEpisodeImagesAsync()` in `RefreshCacheAsync()`.

---

## Completed Tasks

- [x] Series TVDb image lookup and caching (v0.9.10.0)
- [x] Language indicator stripping (v0.9.10.0)
- [x] Title Override Map for ambiguous series (v0.9.11.0)
- [x] Cache invalidation on TVDb setting changes (v0.9.12.0)
- [x] Season artwork fallback chain (v0.9.13.0)
- [x] Episode name display fix (v0.9.13.0)
- [x] Metadata language preference (v0.9.13.0)

---

## References

- [TVDb API v4 Documentation](https://thetvdb.github.io/v4-api/)
- [jellyfin-plugin-tvdb GitHub](https://github.com/jellyfin/jellyfin-plugin-tvdb)
- [TvdbEpisodeProvider.cs source](https://github.com/jellyfin/jellyfin-plugin-tvdb/blob/master/Jellyfin.Plugin.Tvdb/Providers/TvdbEpisodeProvider.cs)
- [TvdbEpisodeImageProvider.cs source](https://github.com/jellyfin/jellyfin-plugin-tvdb/blob/master/Jellyfin.Plugin.Tvdb/Providers/TvdbEpisodeImageProvider.cs)
