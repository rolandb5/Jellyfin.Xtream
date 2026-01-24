// Copyright (C) 2022  Kevin Jilissen

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using MediaBrowser.Model.Tasks;

namespace Jellyfin.Xtream.Tasks;

/// <summary>
/// Scheduled task for refreshing series cache with progress tracking.
/// </summary>
public class SeriesCacheRefreshTask : IScheduledTask
{
    /// <inheritdoc />
    public string Name => "Refresh Xtream Series Cache";

    /// <inheritdoc />
    public string Description => "Pre-fetches and caches all series data (categories, series, seasons, episodes) for faster navigation.";

    /// <inheritdoc />
    public string Category => "Xtream";

    /// <inheritdoc />
    public string Key => "XtreamSeriesCacheRefresh";

    /// <summary>
    /// Gets a value indicating whether this task is hidden from the UI.
    /// </summary>
    public bool IsHidden => false;

    /// <summary>
    /// Gets a value indicating whether this task is enabled.
    /// </summary>
    public bool IsEnabled => true;

    /// <summary>
    /// Gets a value indicating whether this task should be logged.
    /// </summary>
    public bool IsLogged => true;

    /// <inheritdoc />
    public async Task ExecuteAsync(IProgress<double> progress, CancellationToken cancellationToken)
    {
        if (Plugin.Instance?.SeriesCacheService == null)
        {
            return;
        }

        // The SeriesCacheService will report progress through its own mechanism
        // We just trigger the refresh and let it handle progress reporting
        await Plugin.Instance.SeriesCacheService.RefreshCacheAsync(progress, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Executes the task without progress reporting.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task representing the async operation.</returns>
    public Task ExecuteAsync(CancellationToken cancellationToken)
    {
        return ExecuteAsync(new Progress<double>(), cancellationToken);
    }

    /// <inheritdoc />
    public IEnumerable<TaskTriggerInfo> GetDefaultTriggers()
    {
        // No default triggers - task is manual only
        return Array.Empty<TaskTriggerInfo>();
    }
}
