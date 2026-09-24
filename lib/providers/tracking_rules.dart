import '../models/json_utils.dart';
import '../models/media_item.dart';

/// Rounds a percent value to the two decimals `numeric(5, 2)` can store, so a
/// page → percent computation cannot drift (or overflow) in the database.
double roundPercent(num value) {
  final clamped = value.clamp(0, 100).toDouble();
  return double.parse(clamped.toStringAsFixed(2));
}

/// The columns to write when the user picks a new [status].
///
/// The automation is deliberately conservative — it only ever **fills gaps**:
///
///  * `planned`   → resets progress to 0 and clears both timestamps.
///  * `in_progress` → sets `started_at` **only when it is still empty**.
///  * `completed` → sets `completed_at` **only when it is still empty** and
///    forces the progress to 100 % (the last page for a book).
///  * `dropped`   → nothing beyond the status itself.
///
/// Manually entered values are never overwritten.
Map<String, dynamic> statusChangeFields(
  MediaItem item,
  MediaStatus status, {
  DateTime? now,
}) {
  final fields = <String, dynamic>{'status': status.wire};
  switch (status) {
    case MediaStatus.planned:
      // Back to the shelf: forget how far the user got and when.
      fields['progress_percent'] = 0;
      fields['progress_current'] = null;
      fields['started_at'] = null;
      fields['completed_at'] = null;
    case MediaStatus.inProgress:
      if (item.startedAt == null) {
        fields['started_at'] = isoDateTime(now ?? DateTime.now());
      }
    case MediaStatus.completed:
      if (item.completedAt == null) {
        fields['completed_at'] = isoDateTime(now ?? DateTime.now());
      }
      fields['progress_percent'] = 100;
      if (item.kind == MediaKind.book && (item.totalPages ?? 0) > 0) {
        fields['progress_current'] = item.totalPages;
      }
    case MediaStatus.dropped:
      break;
  }
  return fields;
}

/// The columns to write when the user drags the percent slider to [percent].
///
/// For a book with a known page count the current page is kept in sync, and
/// reaching 100 % completes the item ([_completionFields]) unless it was
/// explicitly dropped.
Map<String, dynamic> progressPercentFields(
  MediaItem item,
  num percent, {
  DateTime? now,
}) {
  final value = roundPercent(percent);
  final fields = <String, dynamic>{'progress_percent': value};

  final total = item.totalPages;
  if (item.kind == MediaKind.book && total != null && total > 0) {
    fields['progress_current'] = (value / 100 * total).round().clamp(0, total);
  }
  fields.addAll(_completionFields(item, value, now));
  return fields;
}

/// The columns to write when the user enters page [page] for a book with a
/// known [MediaItem.totalPages].
///
/// The percent value is derived from the page and stored alongside it; the last
/// page completes the item ([_completionFields]).
Map<String, dynamic> progressPageFields(
  MediaItem item,
  int page, {
  DateTime? now,
}) {
  final total = item.totalPages;
  if (total == null || total <= 0) {
    // Without a page count we cannot derive a percent value — the caller falls
    // back to the percent slider in that case, but stay defensive.
    return <String, dynamic>{'progress_current': page < 0 ? 0 : page};
  }
  final clamped = page.clamp(0, total);
  final value = roundPercent(clamped / total * 100);
  final fields = <String, dynamic>{
    'progress_current': clamped,
    'progress_percent': value,
  };
  fields.addAll(_completionFields(item, value, now));
  return fields;
}

/// The column to write when the user edits the total page count.
///
/// When the book already has a current page, the percent value is recomputed so
/// the bar stays consistent; otherwise only `total_pages` is touched.
Map<String, dynamic> totalPagesFields(MediaItem item, int? totalPages) {
  final total = (totalPages != null && totalPages > 0) ? totalPages : null;
  final fields = <String, dynamic>{'total_pages': total};
  final current = item.progressCurrent;
  if (total != null && current != null) {
    fields['progress_current'] = current.clamp(0, total);
    fields['progress_percent'] = roundPercent(current / total * 100);
  }
  return fields;
}

/// The column to write when the user edits the "started on" timestamp.
Map<String, dynamic> startedAtFields(DateTime? value) => <String, dynamic>{
  'started_at': isoDateTime(value),
};

/// The column to write when the user edits the "completed on" timestamp.
Map<String, dynamic> completedAtFields(DateTime? value) => <String, dynamic>{
  'completed_at': isoDateTime(value),
};

/// The signed page delta to write to the reading log for a tracking change.
///
/// This is the **single funnel** of the feature: every progress/status write
/// goes through it, so "pages read" can never be double-counted or missed by
/// one code path. It is a pure function of the *current* [item] and the
/// [fields] about to be written, which keeps the rule testable on its own
/// (no widget, no database).
///
/// Returns `null` when nothing must be logged:
///
///  * **Never for non-books** — movies/series have no page position.
///  * **Never for a book without `total_pages`** — such a book is tracked by
///    pure percent, it has no page position and therefore no reading delta.
///  * **Never when `progress_current` is not part of the write** (e.g. only a
///    timestamp, or the percent of a page-less book was edited).
///  * **Never for a delta of `0`** — an unchanged position is not an entry
///    (logging `0` rows would bloat the table without adding information).
///
/// Otherwise the difference between the new and the previous position is
/// returned: positive for reading (`120 → 200` ⇒ `+80`), negative for a
/// correction (`200 → 180` ⇒ `-20`). Clearing the position (`progress_current`
/// written as `null`, e.g. the `planned` reset) counts as `0`, so the whole
/// reduction is logged as a negative delta.
///
/// Note this also covers the derived `progress_current` that
/// [totalPagesFields] writes when a corrected `total_pages` clamps the current
/// page: the position really did change, so it is logged as a correction.
int? readingLogDelta(MediaItem item, Map<String, dynamic> fields) {
  // Only books carry a meaningful page position.
  if (item.kind != MediaKind.book) return null;

  // A book without a page count is tracked purely by percent — no page
  // position exists, so there is nothing to log. (Commented on purpose:
  // this is the documented behaviour of the feature.)
  final total = item.totalPages;
  if (total == null || total <= 0) return null;

  // No page position in this write → the position cannot have changed.
  if (!fields.containsKey('progress_current')) return null;

  final previous = item.progressCurrent ?? 0;
  final raw = fields['progress_current'];
  // An explicit `null` means "back to the start" (the `planned` reset).
  final next = raw == null ? 0 : (jsonInt(raw) ?? 0);
  final delta = next - previous;
  if (delta == 0) return null;
  return delta;
}

/// Automation shared by both progress writers: 100 % completes the item, sets
/// `completed_at` if still empty — but never touches an explicitly dropped one.
Map<String, dynamic> _completionFields(
  MediaItem item,
  double percent,
  DateTime? now,
) {
  if (percent < 100 || item.status == MediaStatus.dropped) {
    return const <String, dynamic>{};
  }
  return <String, dynamic>{
    'status': MediaStatus.completed.wire,
    if (item.completedAt == null)
      'completed_at': isoDateTime(now ?? DateTime.now()),
  };
}
