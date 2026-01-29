# TVDb Artwork Injection - Test Plan

## Document Info
- **Status:** Implemented
- **Version:** 0.9.11.0 (initial), 0.9.12.0 (hardened)
- **Last Updated:** 2026-01-28
- **Related:** [REQUIREMENTS.md](./REQUIREMENTS.md), [IMPLEMENTATION.md](./IMPLEMENTATION.md)

---

## Test Suites

### Suite 1: TVDb Lookup — Basic Search

Tests that series are correctly looked up on TVDb by name.

| # | Test Case | Steps | Expected Result | Status |
|---|-----------|-------|-----------------|--------|
| 1.1 | Series with exact TVDb match | Enable TVDb, refresh cache for a well-known series (e.g., "Breaking Bad") | TVDb image URL cached, series displays TVDb artwork | Manual |
| 1.2 | Series with no TVDb match | Enable TVDb, refresh cache for an obscure/provider-specific series | No TVDb image cached, Xtream cover used as fallback | Manual |
| 1.3 | Series with placeholder image on TVDb | Enable TVDb, series exists on TVDb but has no artwork | TVDb placeholder filtered out (`missing/series`), Xtream cover used | Manual |
| 1.4 | TVDb disabled | Disable `UseTvdbForSeriesMetadata`, refresh cache | No TVDb lookups performed, all series use Xtream cover | Manual |
| 1.5 | Provider manager unavailable | (Edge case) `_providerManager` is null | `LookupAndCacheTmdbImageAsync` returns null, no crash | Code review |
| 1.6 | Empty series name | Series with empty/whitespace name after `ParseName()` | Lookup skipped, returns null | Code review |

---

### Suite 2: Title Overrides

Tests the manual `Title=TVDbID` override system.

| # | Test Case | Steps | Expected Result | Status |
|---|-----------|-------|-----------------|--------|
| 2.1 | Valid override mapping | Add `Knabbel en Babbel: Park Life=403215` to overrides, refresh cache | Series looks up TVDb ID 403215 directly, correct artwork displayed | Manual |
| 2.2 | Override with invalid TVDb ID | Add `Some Show=999999999` (non-existent ID), refresh cache | Override lookup returns no image, falls back to name search | Manual |
| 2.3 | Override fallback to name search | Add override with bad ID, but series has a TVDb name match | After override fails, name search finds the series | Manual |
| 2.4 | Multiple overrides | Add 3+ overrides, refresh cache | All overrides applied correctly | Manual |
| 2.5 | Case-insensitive matching | Override key uses different case than cleaned series name | Override still matches (case-insensitive dictionary) | Manual |
| 2.6 | Empty overrides textarea | Leave `TvdbTitleOverrides` empty | No overrides parsed, all series use name search | Manual |
| 2.7 | Malformed override lines | Add lines without `=`, empty lines, `=` at start/end | Malformed lines ignored, valid lines processed | Code review |
| 2.8 | Override with spaces around `=` | `Show Name = 123456` (spaces around equals) | Key and value trimmed, override works correctly | Code review |

**Override format edge cases:**

| Input Line | Parsed Key | Parsed Value | Notes |
|-----------|-----------|-------------|-------|
| `Show=123` | `Show` | `123` | Normal case |
| `Show Name=123456` | `Show Name` | `123456` | Spaces in key |
| `=123` | (skipped) | (skipped) | No key |
| `Show=` | (skipped) | (skipped) | No value |
| `Show` | (skipped) | (skipped) | No equals sign |
| ` Show = 123 ` | `Show` | `123` | Trimmed |
| `a=b=c` | `a` | `b=c` | First `=` only |

---

### Suite 3: Language Indicator Stripping

Tests that language indicators are removed before TVDb search.

| # | Test Case | Input Name | Search Terms Generated | Status |
|---|-----------|-----------|----------------------|--------|
| 3.1 | NL Gesproken | `"Show Name (NL Gesproken)"` | `["Show Name (NL Gesproken)", "Show Name"]` | Code review |
| 3.2 | DE | `"Show Name (DE)"` | `["Show Name (DE)", "Show Name"]` | Code review |
| 3.3 | FR | `"Show Name (FR)"` | `["Show Name (FR)", "Show Name"]` | Code review |
| 3.4 | Dutch | `"Show Name (Dutch)"` | `["Show Name (Dutch)", "Show Name"]` | Code review |
| 3.5 | Dubbed | `"Show Name (Dubbed)"` | `["Show Name (Dubbed)", "Show Name"]` | Code review |
| 3.6 | Subbed | `"Show Name (Subbed)"` | `["Show Name (Subbed)", "Show Name"]` | Code review |
| 3.7 | No language indicator | `"Breaking Bad"` | `["Breaking Bad"]` | Code review |
| 3.8 | Multiple indicators | `"Show (NL Gesproken) (DE)"` | `["Show (NL Gesproken) (DE)", "Show"]` | Code review |
| 3.9 | Non-matching parentheses | `"Show (Season 2)"` | `["Show (Season 2)"]` | Code review |
| 3.10 | Nederlands | `"Show (Nederlands)"` | `["Show (Nederlands)", "Show"]` | Code review |
| 3.11 | Deutsch | `"Show (Deutsch)"` | `["Show (Deutsch)", "Show"]` | Code review |

---

### Suite 4: Image Fallback Chain

Tests the complete fallback chain for series artwork.

| # | Test Case | TVDb Override | TVDb Search | Xtream Cover | Expected Image |
|---|-----------|-------------|-------------|-------------|---------------|
| 4.1 | TVDb override found | Image URL | (not checked) | "xtream.jpg" | TVDb override image |
| 4.2 | TVDb override fails, search succeeds | No image | Image URL | "xtream.jpg" | TVDb search image |
| 4.3 | TVDb override fails, search fails | No image | No image | "xtream.jpg" | Xtream cover |
| 4.4 | No override, search succeeds | (no override) | Image URL | "xtream.jpg" | TVDb search image |
| 4.5 | No override, search fails | (no override) | No image | "xtream.jpg" | Xtream cover |
| 4.6 | TVDb disabled | (skipped) | (skipped) | "xtream.jpg" | Xtream cover |
| 4.7 | Both TVDb and Xtream empty | (skipped) | No image | null | No image (Jellyfin default) |

---

### Suite 5: Cache Invalidation

Tests that TVDb settings changes correctly invalidate the cache.

| # | Test Case | Steps | Expected Result | Status |
|---|-----------|-------|-----------------|--------|
| 5.1 | Toggle TVDb on | TVDb was off, toggle on, save settings | Cache hash changes, new refresh fetches TVDb images | Manual |
| 5.2 | Toggle TVDb off | TVDb was on, toggle off, save settings | Cache hash changes, new refresh skips TVDb lookups | Manual |
| 5.3 | Add title override | Add new override line, save settings | Cache hash changes, new refresh uses override | Manual |
| 5.4 | Remove title override | Remove an override line, save settings | Cache hash changes, that series falls back to name search | Manual |
| 5.5 | Modify title override | Change TVDb ID for an existing override, save settings | Cache hash changes, series gets new artwork | Manual |
| 5.6 | Cancel running refresh | Start refresh, change overrides mid-refresh, save | Running refresh cancelled, new refresh starts with new overrides | Manual |
| 5.7 | No TVDb change | Save settings without modifying TVDb options | Cache hash unchanged (if no other changes), no re-fetch | Manual |

---

### Suite 6: Error Handling

Tests graceful handling of various error conditions.

| # | Test Case | Steps | Expected Result | Status |
|---|-----------|-------|-----------------|--------|
| 6.1 | TVDb network error during search | Simulate network failure during TVDb lookup | Error logged at WARNING, series falls back to Xtream cover | Code review |
| 6.2 | TVDb returns empty results | Series name doesn't match anything on TVDb | Warning logged, null returned, Xtream cover used | Code review |
| 6.3 | Cancellation during TVDb lookup | Cancel cache refresh while TVDb lookups are running | `OperationCanceledException` propagates, refresh stops cleanly | Code review |
| 6.4 | ParseName returns empty | Series with name that's all tags (e.g., `[TAG][TAG2]`) | Lookup skipped (empty cleanName), returns null | Code review |
| 6.5 | Provider manager throws | `_providerManager.GetRemoteSearchResults()` throws | Exception caught, warning logged, null returned | Code review |

---

### Suite 7: UI Integration

Tests the configuration UI for TVDb settings.

| # | Test Case | Steps | Expected Result | Status |
|---|-----------|-------|-----------------|--------|
| 7.1 | TVDb toggle loads state | Open Series settings page | Toggle reflects saved `UseTvdbForSeriesMetadata` value | Manual |
| 7.2 | TVDb options visibility | Toggle TVDb on/off | Override textarea section shows/hides accordingly | Manual |
| 7.3 | Override textarea loads content | Open Series settings after saving overrides | Textarea contains previously saved override text | Manual |
| 7.4 | Save TVDb settings | Change toggle and overrides, click Save | Settings saved correctly, config updated | Manual |
| 7.5 | TVDb settings persist | Save, navigate away, return to page | Settings still reflect saved values | Manual |
| 7.6 | Default state | Fresh install, open Series settings | TVDb enabled (default: true), overrides empty | Manual |

---

## Performance Benchmarks

### TVDb Lookup Duration

| Library Size | Lookup Time | Notes |
|-------------|-------------|-------|
| 50 series | ~30 seconds | Small library |
| 200 series | ~2 minutes | Medium library |
| 666 series | ~5 minutes | Large library (observed) |

**Rate:** ~2 series per second (sequential, with network latency)

### Cache Impact

| Metric | Without TVDb | With TVDb |
|--------|-------------|-----------|
| Cache refresh time | 5-15 min | 7-20 min |
| Memory per series | ~1KB | ~1.1KB (+URL string) |
| Browsing performance | Instant | Instant (no difference) |

### Match Rate (Observed)

From production logs (666 series library):

| Category | Count | Percentage |
|----------|-------|-----------|
| TVDb match found | ~600 | ~90% |
| No TVDb match | ~66 | ~10% |
| Override matches | 5-10 | ~1% |

---

## Regression Tests

Tests to verify TVDb feature doesn't break existing functionality.

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| R.1 | Series browsing works | Browse series library | All series display with correct names and artwork |
| R.2 | Season/episode browsing works | Open a series, browse seasons and episodes | Seasons and episodes load correctly |
| R.3 | Cache refresh completes | Trigger full cache refresh | Refresh completes without errors |
| R.4 | Xtream cover still works | Disable TVDb, check series artwork | Xtream cover images display correctly |
| R.5 | Category save guard intact | Open Series settings with failed category load | "Cannot save" guard prevents config wipe |

---

## References

- [REQUIREMENTS.md](./REQUIREMENTS.md) - Feature requirements
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Design decisions
- [IMPLEMENTATION.md](./IMPLEMENTATION.md) - Code changes
- [CHANGELOG.md](./CHANGELOG.md) - Version history
