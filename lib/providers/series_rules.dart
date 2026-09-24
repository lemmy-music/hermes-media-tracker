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
