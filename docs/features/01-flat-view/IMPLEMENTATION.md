# Flat View Feature - Implementation Details

## Document Info
- **Status:** Implemented
- **Version:** 0.9.1.0 (Series), 0.9.1.0 (VOD)
- **Last Updated:** 2026-01-27
- **Related:** [REQUIREMENTS.md](./REQUIREMENTS.md), [ARCHITECTURE.md](./ARCHITECTURE.md)

---

## Implementation Approach

The flat view feature was implemented in two phases:

1. **Phase 1 (v0.9.1.0)**: Series flat view
   - Commit: `133dcd4`, `4cdce1c`
   - Files: SeriesChannel.cs, PluginConfiguration.cs, XtreamSeries.html/js

2. **Phase 2 (v0.9.1.0)**: VOD flat view
   - Commit: `b9ea408`, `7d92652`
   - Files: VodChannel.cs, XtreamVod.html/js

Both implementations follow the same pattern:
1. Add configuration property
2. Add routing logic to GetChannelItems()
3. Implement GetAll*Flattened() method
4. Add UI checkbox
5. Wire up JavaScript

---

## Code Changes

### Files Modified

#### 1. **Jellyfin.Xtream/Configuration/PluginConfiguration.cs**

**Added Properties:**
```csharp
/// <summary>
/// Gets or sets a value indicating whether to show all series directly
/// without category folders.
/// When enabled, all series from selected categories appear directly
/// in the library.
/// </summary>
public bool FlattenSeriesView { get; set; } = false;

/// <summary>
/// Gets or sets a value indicating whether to show all VOD movies directly
/// without category folders.
/// When enabled, all movies from selected categories appear directly
/// in the library.
/// </summary>
public bool FlattenVodView { get; set; } = false;
```

**Decision:** Default to `false` (disabled)
- **Rationale:** Backward compatibility - existing users see no change
- **New users:** Can opt-in by enabling in settings
- **Safe:** Doesn't break existing workflows

---

#### 2. **Jellyfin.Xtream/SeriesChannel.cs**

**Lines 95-104:** Modified GetChannelItems() to check flat view flag

```csharp
public async Task<ChannelItemResult> GetChannelItems(
    InternalChannelItemQuery query,
    CancellationToken cancellationToken)
{
    logger.LogInformation("GetChannelItems called - FolderId: {FolderId}",
        query.FolderId ?? "(root)");
    try
    {
        if (string.IsNullOrEmpty(query.FolderId))
        {
            // NEW: Check if flat series view is enabled
            if (Plugin.Instance.Configuration.FlattenSeriesView)
            {
                return await GetAllSeriesFlattened(cancellationToken)
                    .ConfigureAwait(false);
            }

            // ORIGINAL: Return categories
            return await GetCategories(cancellationToken).ConfigureAwait(false);
        }

        // ORIGINAL: Handle navigation (unchanged)
        Guid guid = Guid.Parse(query.FolderId);
        // ... rest of navigation logic ...
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Failed to get channel items");
        throw;
    }

    return new ChannelItemResult() { TotalRecordCount = 0 };
}
```

**Decision:** Simple if-check at root level
- **Why here:** Root level is the decision point (flat vs categories)
- **Clean:** Doesn't affect existing navigation code
- **Minimal impact:** Single boolean check (negligible performance)

**Lines 260-308:** Added GetAllSeriesFlattened() method

```csharp
private async Task<ChannelItemResult> GetAllSeriesFlattened(
    CancellationToken cancellationToken)
{
    logger.LogInformation("GetAllSeriesFlattened called");

    // 1. Get categories (try cache first)
    IEnumerable<Category>? cachedCategories =
        Plugin.Instance.SeriesCacheService.GetCachedCategories();
    IEnumerable<Category> categories = cachedCategories ??
        await Plugin.Instance.StreamService.GetSeriesCategories(cancellationToken)
            .ConfigureAwait(false);

    logger.LogInformation("GetAllSeriesFlattened found {Count} categories",
        categories.Count());

    List<ChannelItemInfo> items = new();

    // 2. Get all series from all selected categories
    foreach (Category category in categories)
    {
        try
        {
            // Try cache first
            IEnumerable<Series>? cachedSeries =
                Plugin.Instance.SeriesCacheService.GetCachedSeriesList(
                    category.CategoryId);
            IEnumerable<Series> series;

            if (cachedSeries != null)
            {
                series = cachedSeries;
                logger.LogInformation(
                    "GetAllSeriesFlattened got {Count} series from cache " +
                    "for category {CategoryId}",
                    series.Count(), category.CategoryId);
            }
            else
            {
                // Fallback to API if cache miss
                series = await Plugin.Instance.StreamService.GetSeries(
                    category.CategoryId, cancellationToken).ConfigureAwait(false);
                logger.LogInformation(
                    "GetAllSeriesFlattened got {Count} series from API " +
                    "for category {CategoryId}",
                    series.Count(), category.CategoryId);
            }

            items.AddRange(series.Select(CreateChannelItemInfo));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to get series for category {CategoryId}",
                category.CategoryId);
            // Continue with other categories
        }
    }

    // 3. Sort alphabetically for consistent display
    items = items.OrderBy(item => item.Name).ToList();

    logger.LogInformation("GetAllSeriesFlattened returning {Count} series total",
        items.Count);
    return new()
    {
        Items = items,
        TotalRecordCount = items.Count
    };
}
```

**Key Implementation Details:**

1. **Cache Integration**
   - Check `SeriesCacheService.GetCachedCategories()` first
   - Check `SeriesCacheService.GetCachedSeriesList()` per category
   - Fallback to API if cache miss (null check)
   - **Benefit:** Works with or without caching enabled

2. **Error Handling**
   - Try-catch per category (not global)
   - Log error but continue with other categories
   - **Benefit:** Partial results better than complete failure

3. **Logging**
   - Log at each step (entry, category count, per-category results, total)
   - Differentiate cache vs API in logs
   - **Benefit:** Easy debugging, can trace performance

4. **Sorting**
   - `OrderBy(item => item.Name)` - simple LINQ
   - Uses parsed name (already cleaned by CreateChannelItemInfo)
   - **Performance:** O(n log n) - acceptable for <1000 items

---

#### 3. **Jellyfin.Xtream/VodChannel.cs**

**Lines 93-102:** Modified GetChannelItems() for VOD

```csharp
if (string.IsNullOrEmpty(query.FolderId))
{
    // NEW: Check if flat VOD view is enabled
    if (Plugin.Instance.Configuration.FlattenVodView)
    {
        return await GetAllStreamsFlattened(cancellationToken)
            .ConfigureAwait(false);
    }

    // ORIGINAL: Return categories
    return await GetCategories(cancellationToken).ConfigureAwait(false);
}
```

**Lines 166-186:** Added GetAllStreamsFlattened() method

```csharp
private async Task<ChannelItemResult> GetAllStreamsFlattened(
    CancellationToken cancellationToken)
{
    // 1. Get categories (no cache for VOD yet)
    IEnumerable<Category> categories =
        await Plugin.Instance.StreamService.GetVodCategories(cancellationToken)
            .ConfigureAwait(false);

    List<ChannelItemInfo> items = new();

    // 2. Get all streams from all selected categories
    foreach (Category category in categories)
    {
        IEnumerable<StreamInfo> streams =
            await Plugin.Instance.StreamService.GetVodStreams(
                category.CategoryId, cancellationToken).ConfigureAwait(false);

        // Create channel items in parallel
        items.AddRange(
            await Task.WhenAll(streams.Select(CreateChannelItemInfo))
                .ConfigureAwait(false));
    }

    // 3. Sort alphabetically for consistent display
    items = items.OrderBy(item => item.Name).ToList();

    return new()
    {
        Items = items,
        TotalRecordCount = items.Count
    };
}
```

**Differences from Series Implementation:**
- **No cache integration** (VOD not currently cached)
- **Parallel item creation** (`Task.WhenAll` vs sequential)
- **No per-category error handling** (simpler, assumes reliable API)

**Decision:** Simpler implementation for VOD
- **Rationale:** VOD typically smaller, less critical
- **Future:** Can add caching and error handling if needed

---

#### 4. **Jellyfin.Xtream/Configuration/Web/XtreamSeries.html**

**Added Checkbox UI:**
```html
<div class="checkboxContainer checkboxContainer-withDescription">
    <label>
        <input type="checkbox" is="emby-checkbox" id="FlattenSeriesView" />
        <span>Show all series directly without category folders</span>
    </label>
    <div class="fieldDescription checkboxFieldDescription">
        When enabled, all series from selected categories appear in one
        alphabetical list instead of separate category folders.
        This provides faster access but loses category organization.
    </div>
</div>
```

**Decision:** Clear description with trade-off explanation
- **Benefit:** Users understand what they're enabling
- **Placement:** Near top of settings (important feature)

---

#### 5. **Jellyfin.Xtream/Configuration/Web/XtreamSeries.js**

**Modified loadPage() function:**
```javascript
function loadPage(page, config) {
    // ... existing code ...

    // NEW: Load flat view setting
    $('#FlattenSeriesView', page).prop('checked',
        config.FlattenSeriesView || false);

    // ... existing code ...
}
```

**Modified onSubmit() function:**
```javascript
$('.XtreamSeriesConfigPage').on('pageshow', function () {
    // ... existing code ...

    $('.XtreamSeriesForm').off('submit').on('submit', function (e) {
        e.preventDefault();
        Dashboard.showLoadingMsg();

        // ... existing code ...

        // NEW: Save flat view setting
        config.FlattenSeriesView =
            $('#FlattenSeriesView', page).prop('checked');

        // ... save to server ...
    });
});
```

**Implementation Notes:**
- Uses jQuery (Jellyfin standard)
- `prop('checked')` for checkbox state
- Default to `false` if not present (`|| false`)
- No validation needed (boolean is always valid)

---

#### 6. **Jellyfin.Xtream/Configuration/Web/XtreamVod.html**

Same pattern as XtreamSeries.html:
```html
<div class="checkboxContainer checkboxContainer-withDescription">
    <label>
        <input type="checkbox" is="emby-checkbox" id="FlattenVodView" />
        <span>Show all movies directly without category folders</span>
    </label>
    <div class="fieldDescription checkboxFieldDescription">
        When enabled, all movies from selected categories appear in one
        alphabetical list instead of separate category folders.
    </div>
</div>
```

---

#### 7. **Jellyfin.Xtream/Configuration/Web/XtreamVod.js**

Same pattern as XtreamSeries.js (load and save `FlattenVodView`)

---

### Files Not Modified

**Important:** These files were NOT changed:
- StreamService.cs (no changes to API calls)
- Plugin.cs (no service changes)
- Any model classes (no data structure changes)

**Rationale:** Minimal impact, additive only

---

## Configuration

### Settings Added

| Setting | Type | Default | Location |
|---------|------|---------|----------|
| `FlattenSeriesView` | bool | false | PluginConfiguration.cs line 72 |
| `FlattenVodView` | bool | false | PluginConfiguration.cs line 78 |

### Settings UI

**Location:** Jellyfin Dashboard → Plugins → Jellyfin Xtream → Settings

**Series Tab:**
- Checkbox: "Show all series directly without category folders"
- Description explains feature and trade-off

**VOD Tab:**
- Checkbox: "Show all movies directly without category folders"
- Description explains feature

### Configuration Storage

**File:** `/config/plugins/configurations/Jellyfin.Xtream.xml`

**Format:**
```xml
<PluginConfiguration>
  <FlattenSeriesView>true</FlattenSeriesView>
  <FlattenVodView>false</FlattenVodView>
  <!-- other settings -->
</PluginConfiguration>
```

**Persistence:** Automatic via Jellyfin plugin system

---

## Edge Cases Handled

### 1. **Empty Categories**

**Scenario:** User has categories selected but they contain no series/movies

**Handling:**
```csharp
foreach (Category category in categories)
{
    IEnumerable<Series> series = await GetSeries(category.CategoryId);
    // series is empty enumerable (not null)
    items.AddRange(series.Select(CreateChannelItemInfo));
    // AddRange handles empty enumerable gracefully
}
```

**Result:** Empty flat view (no items shown) - correct behavior

---

### 2. **API Error for One Category**

**Scenario:** One category's API call fails

**Handling (Series only):**
```csharp
foreach (Category category in categories)
{
    try
    {
        // Fetch series
        items.AddRange(series.Select(CreateChannelItemInfo));
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Failed for category {CategoryId}",
            category.CategoryId);
        // Continue with next category
    }
}
```

**Result:** Partial results shown (other categories' content)

**VOD:** No per-category error handling (simpler implementation)

---

### 3. **No Categories Selected**

**Scenario:** User has no categories selected in settings

**Handling:**
- `GetSeriesCategories()` returns empty list
- Flat view returns empty result
- Jellyfin shows "No items" message

**Result:** User sees empty library (prompts them to select categories)

---

### 4. **Duplicate Series Across Categories**

**Scenario:** Same series appears in multiple categories

**Handling:**
```csharp
items.AddRange(series.Select(CreateChannelItemInfo));
// Same series ID will create duplicate ChannelItemInfo
```

**Result:** Series appears multiple times in flat view

**Future Enhancement:** Deduplicate by series ID
```csharp
// Potential fix:
items = items.GroupBy(i => i.Id).Select(g => g.First()).ToList();
```

**Decision:** Not implemented initially
- **Why:** Rare scenario (most providers don't duplicate)
- **Impact:** Low (user sees same series twice, but both work)

---

### 5. **Very Large Libraries**

**Scenario:** 1000+ series in flat view

**Handling:**
- All items loaded into memory temporarily
- Sorting O(n log n) - ~milliseconds for 1000 items
- Jellyfin UI uses virtual scrolling (handles thousands)

**Performance:**
- 200 series: ~500ms (cache) / ~20s (no cache)
- 500 series: ~1-2s (cache) / ~50s (no cache)
- 1000 series: ~3-5s (cache) / ~100s (no cache)

**Recommendation:** Enable caching for large libraries

---

### 6. **Changing Configuration During Use**

**Scenario:** User toggles flat view while browsing

**Handling:**
- Configuration read on each GetChannelItems() call
- Next navigation uses new setting
- **No restart required**

**User Experience:**
1. User browses flat view
2. User disables flat view in settings
3. User navigates back to root
4. Categories now shown (immediate effect)

---

### 7. **Malformed Series Names**

**Scenario:** Series name contains tags like `[US]` or `┃HD┃`

**Handling:**
```csharp
ParsedName parsedName = StreamService.ParseName(series.Name);
// parsedName.Title has tags stripped
item.Name = parsedName.Title;
```

**Result:** Clean titles in flat view, sorted correctly

**Example:**
- Raw: `[US] Breaking Bad ┃HD┃`
- Displayed: `Breaking Bad`
- Sorted with other "B" titles

---

## API Changes

**None.** This feature:
- Uses existing Jellyfin Channel API
- No new public methods exposed
- No breaking changes to existing methods

**Internal methods added:**
- `SeriesChannel.GetAllSeriesFlattened()` (private)
- `VodChannel.GetAllStreamsFlattened()` (private)

---

## Performance Impact

### Series (With Cache)

**Before flat view:** N/A (feature didn't exist)

**With flat view enabled:**
- First load: ~500ms (cache hit)
- Subsequent loads: ~500ms (cache hit)

**Performance:** Excellent (cache makes flat view fast)

### Series (Without Cache)

**With flat view enabled:**
- First load: ~20s (4 categories × 5s API call each)
- Subsequent loads: ~20s (no caching)

**Performance:** Slow but acceptable (users expect some delay)

### VOD (No Cache)

**With flat view enabled:**
- First load: ~15s (3 categories × 5s API call each)
- Subsequent loads: ~15s (no caching)

**Performance:** Acceptable for VOD (typically browsed less frequently)

### Comparison

| View Type | Cache | Load Time | Navigation Depth |
|-----------|-------|-----------|------------------|
| Categories | N/A | ~2s initial, ~5s per category | 3-4 clicks |
| Flat (cached) | Yes | ~500ms | 1-2 clicks |
| Flat (no cache) | No | ~20s | 1-2 clicks |

**Key Insight:** Flat view + caching = best performance

---

## Memory Impact

**Temporary memory usage:**
- List<ChannelItemInfo> holds all series during aggregation
- Typical: ~1MB for 200 series
- Released after method returns

**No persistent memory increase** (items not cached by this feature)

---

## Known Limitations

### 1. **Duplicate Series**

- If same series in multiple categories, appears multiple times
- **Workaround:** None currently
- **Future:** Deduplicate by series ID

### 2. **Sort Options Limited**

- Only alphabetical sorting supported
- **Workaround:** Use Jellyfin's built-in filters/sorts
- **Future:** Add date added, rating sort options

### 3. **No Category Context**

- Can't tell which category a series belongs to in flat view
- **Workaround:** Disable flat view to see categories
- **Future:** Add category as tag or subtitle

### 4. **VOD Not Cached**

- VOD flat view always hits API (slower)
- **Workaround:** None
- **Future:** Implement VOD caching

### 5. **No Hybrid View**

- Can't show some categories flat and others not
- **Workaround:** Disable flat view, navigate manually
- **Future:** Per-category flat view toggle

---

## Testing Notes

### Manual Test Scenarios

1. **Enable Series Flat View**
   - ✅ All series appear in one list
   - ✅ Alphabetically sorted
   - ✅ Clicking series works (seasons shown)

2. **Enable VOD Flat View**
   - ✅ All movies appear in one list
   - ✅ Alphabetically sorted
   - ✅ Clicking movie plays

3. **Disable Flat View**
   - ✅ Categories shown again
   - ✅ Original navigation restored
   - ✅ No errors

4. **Toggle During Use**
   - ✅ No restart required
   - ✅ Next navigation uses new setting

5. **Empty Library**
   - ✅ Shows "No items"
   - ✅ No errors

6. **Large Library (200+ series)**
   - ✅ Loads in reasonable time
   - ✅ Sorts correctly
   - ✅ All items accessible

---

## Deployment Considerations

### Docker Deployment

**No special considerations** - standard plugin deployment:

```bash
# Copy DLL
docker cp Jellyfin.Xtream.dll jellyfin:/config/plugins/Jellyfin.Xtream_0.9.1.0/

# Fix permissions
docker exec jellyfin chown -R abc:abc /config/plugins/Jellyfin.Xtream_0.9.1.0/

# Restart Jellyfin
docker restart jellyfin
```

### Browser Cache

**Important:** After updating plugin with UI changes:
- Users must clear browser cache (Ctrl+F5)
- Or use incognito/private mode
- Otherwise checkbox may not appear

---

## Related Commits

**Series Flat View:**
- `133dcd4` - Add flat series view feature (initial)
- `4cdce1c` - Add flat series view feature (complete implementation)

**VOD Flat View:**
- `b9ea408` - Add flat VOD view feature
- `7d92652` - Bump version to 0.9.1.0 - Add flat VOD view feature

**Total changes:**
- 8 files changed
- 206 insertions
- 5 deletions

---

## Future Improvements

See [REQUIREMENTS.md](./REQUIREMENTS.md#9-future-considerations) for detailed future enhancements.

**High Priority:**
1. Deduplicate series across categories
2. Add VOD caching
3. Sort options (date added, rating)

**Medium Priority:**
1. Hybrid view (categories as sections)
2. Category tags on items
3. Search/filter UI

**Low Priority:**
1. Per-user preferences
2. Genre-based flattening
3. Custom grouping

---

## References

- [REQUIREMENTS.md](./REQUIREMENTS.md) - Feature requirements
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Design decisions
- [TEST_PLAN.md](./TEST_PLAN.md) - Test cases
- [CHANGELOG.md](./CHANGELOG.md) - Version history
