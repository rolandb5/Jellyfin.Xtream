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
/// Runs every 10 minutes but only refreshes if the configured interval has passed.
/// </summary>
public class SeriesCacheRefreshTask : IScheduledTask
{
    /// <summary>
    /// Gets the name of the task.
    /// </summary>
    public string Name => "Refresh Xtream Series Cache";

    /// <summary>
    /// Gets the description of the task.
    /// </summary>
    public string Description => "Checks if series cache needs refresh based on configured interval. Refresh frequency is controlled in plugin settings.";

    /// <summary>
    /// Gets the category of the task.
    /// </summary>
    public string Category => "Xtream";

    /// <summary>
    /// Gets the key of the task.
    /// </summary>
    public string Key => "XtreamSeriesCacheRefresh";

    /// <summary>
    /// Gets a value indicating whether the task is hidden.
    /// </summary>
    public bool IsHidden => false;

    /// <summary>
    /// Gets a value indicating whether the task is enabled.
    /// </summary>
    public bool IsEnabled => true;

    /// <summary>
    /// Gets a value indicating whether the task is logged.
    /// </summary>
    public bool IsLogged => true;

    /// <inheritdoc />
    public async Task ExecuteAsync(IProgress<double> progress, CancellationToken cancellationToken)
    {
        if (Plugin.Instance?.SeriesCacheService == null)
        {
            return;
        }

        // Get configured refresh interval (default 60 minutes)
        int refreshIntervalMinutes = Plugin.Instance.Configuration.SeriesCacheExpirationMinutes;
        if (refreshIntervalMinutes <= 0)
        {
            refreshIntervalMinutes = 60;
        }

        // Check if enough time has passed since last refresh
        var (_, _, _, _, lastRefreshComplete) = Plugin.Instance.SeriesCacheService.GetStatus();

        if (lastRefreshComplete.HasValue)
        {
            TimeSpan timeSinceLastRefresh = DateTime.UtcNow - lastRefreshComplete.Value;
            if (timeSinceLastRefresh.TotalMinutes < refreshIntervalMinutes)
            {
                // Not enough time has passed, skip this run
                progress.Report(1.0);
                return;
            }
        }

        // Time to refresh
        await Plugin.Instance.SeriesCacheService.RefreshCacheAsync(progress, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Executes the task without progress reporting.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Task representing the async operation.</returns>
    public Task ExecuteAsync(CancellationToken cancellationToken)
    {
        return ExecuteAsync(new Progress<double>(), cancellationToken);
    }

    /// <summary>
    /// Gets the default triggers for this task.
    /// </summary>
    /// <returns>Default triggers (checks every 10 minutes).</returns>
    public IEnumerable<TaskTriggerInfo> GetDefaultTriggers()
    {
        // Run every 10 minutes as a check interval.
        // The actual refresh only happens if the configured interval has passed.
        // This allows the plugin setting to control refresh frequency without
        // requiring users to manually update the scheduled task.
        return new[]
        {
            new TaskTriggerInfo
            {
                Type = TaskTriggerInfoType.IntervalTrigger,
                IntervalTicks = TimeSpan.FromMinutes(10).Ticks
            }
        };
    }
}
