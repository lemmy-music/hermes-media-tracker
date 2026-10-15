/// Rules that derive the **tracking state of a series from its episodes**.
///
/// Unlike movies and books — where the user picks a status and a percent by
/// hand — a series is tracked per episode. The status and the progress bar are
/// therefore *derived* from how many episodes are checked off and persisted
/// back onto `media_items`, so the library list and the stats screen can keep
/// reading the same columns.
///
/// The automation mirrors [tracking_rules]'s "only fill gaps, never clobber a
/// manual decision" philosophy:
///
///  * `progress_percent` is always written (it is a pure function of the
///    watched count).
///  * `status` becomes `in_progress` on a partial watch and `completed` on a
///    full watch — but **0 watched leaves the status untouched** and an
///    explicitly `dropped` series is **never** switched by the automation.
///  * `started_at` is stamped when the first episode is checked off (if empty).
///  * `completed_at` is stamped when every episode is checked off (if empty).
library;

import '../models/episode.dart';
import '../models/json_utils.dart';
import '../models/media_item.dart';

/// The derived `progress_percent` for [watched] of [total] episodes.
///
/// Rounded to **one** decimal (Daniel's spec), clamped to `0..100`. A series
/// without a known episode count yields `0` instead of dividing by zero.
double seriesProgressPercent(int watched, int total) {
  if (total <= 0) return 0;
  final clamped = watched.clamp(0, total);
  final value = (clamped / total * 100).clamp(0, 100).toDouble();
  return double.parse(value.toStringAsFixed(1));
}

/// The tracking columns to persist after the watched state of a series'
/// episodes changed.
///
/// [watchedCount] / [totalCount] describe the **current** episode set (the
/// caller counts the rows it holds, specials handling decided there). Only
/// keys that actually change are included, so a write never touches columns
/// the automation is not responsible for.
///
/// The `dropped` guard is deliberate: once a user has dropped a series, the
/// episode automation must not silently resurrect it to `in_progress` or
/// `completed` (and it must not overwrite it with something else either).
Map<String, dynamic> seriesDerivedFields(
  MediaItem item, {
  required int watchedCount,
  required int totalCount,
  DateTime? now,
}) {
  final fields = <String, dynamic>{
    'progress_percent': seriesProgressPercent(watchedCount, totalCount),
  };

  final allWatched = totalCount > 0 && watchedCount >= totalCount;
  final nothingWatched = watchedCount <= 0;

  if (item.status != MediaStatus.dropped) {
    if (allWatched) {
      fields['status'] = MediaStatus.completed.wire;
    } else if (!nothingWatched) {
      fields['status'] = MediaStatus.inProgress.wire;
    }
    // `nothingWatched` → leave the status exactly as it is.
  }

  if (!nothingWatched && item.startedAt == null) {
    fields['started_at'] = isoDateTime(now ?? DateTime.now());
  }
  if (allWatched && item.completedAt == null) {
    fields['completed_at'] = isoDateTime(now ?? DateTime.now());
  }

  return fields;
}

/// The still-unwatched episodes of the **same season** that come before
/// [episode] (a lower `episodeNumber`), ascending.
///
/// Backs the per-episode catch-up prompt: when the user checks off an episode
/// and the season still has earlier open episodes, the UI offers to mark them
/// watched too. The returned list is exactly what "Ja, alle davor" writes, and
/// an empty list means **no prompt** (there is nothing to do).
///
/// **Scope decision (documented):** the episode-level prompt only ever looks at
/// earlier episodes of the *same* season. It never reaches back into earlier
/// seasons — that is the job of the season-level [previousSeasonsWithUnwatched]
/// prompt. Keeping the two scopes apart means a per-episode check can never
/// silently mass-mark a whole earlier season.
List<Episode> previousUnwatchedEpisodes(
  List<Episode> episodes,
  Episode episode,
) {
  final result = <Episode>[
    for (final candidate in episodes)
      if (candidate.seasonNumber == episode.seasonNumber &&
          candidate.episodeNumber < episode.episodeNumber &&
          !candidate.watched)
        candidate,
  ]..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
  return result;
}

/// The earlier seasons (`seasonNumber < [seasonNumber]`) that still contain at
/// least one unwatched episode, ascending.
///
/// Backs the season-level catch-up prompt: when the user bulk-marks a season
/// watched and a *previous* season still has open episodes, the UI offers to
/// mark those seasons watched too. An empty list means **no prompt** — either
/// this is the first season or every earlier season is already fully watched.
///
/// The number of entries is the count shown in the dialog ("N Staffeln").
List<int> previousSeasonsWithUnwatched(
  List<Episode> episodes,
  int seasonNumber,
) {
  final seasons = <int>{
    for (final episode in episodes)
      if (episode.seasonNumber < seasonNumber && !episode.watched)
        episode.seasonNumber,
  }.toList()..sort();
  return seasons;
}

/// The season that should be **pre-selected** when the detail view of a series
/// is opened — i.e. the season the user is currently "in".
///
/// [availableSeasons] are the distinct season numbers the series has (ascending
/// preferred, but the function sorts defensively); [episodes] is the full
/// episode set (all seasons) as far as it is currently loaded.
///
/// The rule, matching the user feedback ("opening a series always starts on
/// season 1, even when I'm four seasons in"):
///
///  1. **Nothing watched** → the first season.
///  2. **Something watched** → the season of the **most recently watched**
///     episode (the greatest `watched_at`; a `null` timestamp counts as the
///     oldest, ties are broken by season/episode number so the choice is
///     deterministic).
///  3. If that base season is **completely watched** and a **later** season
///     exists, the **next** available season is pre-selected — that is where
///     the user would continue watching (this also covers the common "finished
///     season 1, haven't started season 2" case).
///  4. If the base season is the **last** season it stays selected (a fully
///     finished series lands on its last season).
///
/// Returns `null` when [availableSeasons] is empty (nothing to select). The
/// function is pure and never touches the widget tree.
int? initialSeasonFor(List<Episode> episodes, List<int> availableSeasons) {
  if (availableSeasons.isEmpty) return null;

  final seasons = List<int>.of(availableSeasons)..sort();

  Episode? latest;
  for (final episode in episodes) {
    if (!episode.watched) continue;
    if (latest == null || _isMoreRecent(episode, latest)) latest = episode;
  }

  // Nothing watched yet → the first season (the previous default).
  if (latest == null) return seasons.first;

  final base = latest.seasonNumber;
  // Defensive: the base season must be one of the selectable seasons.
  if (!seasons.contains(base)) return seasons.first;

  final baseEpisodes = <Episode>[
    for (final episode in episodes)
      if (episode.seasonNumber == base) episode,
  ];
  final fullyWatched =
      baseEpisodes.isNotEmpty &&
      baseEpisodes.every((episode) => episode.watched);

  if (fullyWatched) {
    final later = <int>[
      for (final season in seasons)
        if (season > base) season,
    ];
    if (later.isNotEmpty) return later.first;
  }

  return base;
}

/// Recency order for [initialSeasonFor]: later `watchedAt` first, an unset
/// timestamp is the oldest, and `season`/`episode` number break ties so the
/// comparison is a total order.
bool _isMoreRecent(Episode candidate, Episode current) {
  final candidateAt = candidate.watchedAt;
  final currentAt = current.watchedAt;
  if (candidateAt != null && currentAt != null) {
    final byTime = candidateAt.compareTo(currentAt);
    if (byTime != 0) return byTime > 0;
  } else if (candidateAt != null) {
    return true;
  } else if (currentAt != null) {
    return false;
  }
  final bySeason = candidate.seasonNumber.compareTo(current.seasonNumber);
  if (bySeason != 0) return bySeason > 0;
  return candidate.episodeNumber > current.episodeNumber;
}
