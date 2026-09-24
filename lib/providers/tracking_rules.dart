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
