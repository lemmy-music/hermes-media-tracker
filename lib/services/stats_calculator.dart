/// Pure, testable aggregation rules behind the stats screen.
///
/// Deliberately free of Flutter / Supabase imports: the whole stats feature
/// boils down to *what do these lists of [MediaItem]s and [Episode]s add up
/// to*, so everything here is a pure function of its inputs plus an explicit
/// reference `now`. That keeps the widgets dumb and the numbers unit-testable.
///
/// Conventions used throughout:
///
///  * **Time window** — a [StatsRange] covers the last *n* calendar months
///    **including the current one** (`1` = this month only). The window is
///    half-open: `[start, end)`, i.e. the first instant of the range counts and
///    the first instant *after* it does not. `all` has no bounds.
///  * **Completion date** — movies/books are counted by `completed_at`, *not*
///    by `status`. A row with a completion timestamp is a completion; this is
///    what the product brief asks for and it also handles back-dated entries a
///    user typed in by hand.
///  * **Series** are tracked per episode, so a *watched episode* counts as one
///    completion, bucketed by the episode's `watched_at`.
///  * **Missing data is skipped, never coerced to 0** — a movie without a
///    runtime simply does not contribute to the watch time.
library;

import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/reading_log_entry.dart';

/// The selectable time window of the time-based stats block.
///
/// [months] is the number of calendar months (current month included);
/// `null` means "all time".
enum StatsRange {
  month(1),
  sixMonths(6),
  twelveMonths(12),
  all(null);

  const StatsRange(this.months);

  /// Calendar months spanned, current month included; `null` for all time.
  final int? months;

  /// The default range of the stats screen.
  static const StatsRange defaultRange = StatsRange.twelveMonths;
}

/// Whether a chart's buckets are months or years.
enum BucketGranularity { month, year }

/// One bar of the "completions over time" chart.
///
/// [start] is the first day of the bucket's month (or January 1st of its year).
/// Empty buckets exist on purpose — a month without a completion is rendered
/// as a gap, not dropped.
class StatsBucket {
  const StatsBucket({
    required this.start,
    this.granularity = BucketGranularity.month,
    this.movies = 0,
    this.books = 0,
    this.episodes = 0,
  });

  final DateTime start;
  final BucketGranularity granularity;

  /// Movies completed in this bucket (`completed_at`).
  final int movies;

  /// Books completed in this bucket (`completed_at`).
  final int books;

  /// Series episodes watched in this bucket (`watched_at`) — one per episode.
  final int episodes;

  int get total => movies + books + episodes;

  bool get isEmpty => total == 0;
}

/// The stacked bar series of the "completions over time" chart.
class CompletionsSeries {
  const CompletionsSeries({required this.buckets, required this.granularity});

  final List<StatsBucket> buckets;
  final BucketGranularity granularity;

  /// `true` when no bucket holds a single completion.
  bool get isEmpty => buckets.every((bucket) => bucket.isEmpty);

  /// The tallest bucket — used to size the chart's Y axis.
  int get maxTotal =>
      buckets.fold(0, (max, b) => b.total > max ? b.total : max);
}

/// Watch time in minutes within the selected range.
class WatchTimeStats {
  const WatchTimeStats({
    required this.episodeMinutes,
    required this.movieMinutes,
    required this.hasData,
  });

  /// Runtime of watched episodes (`watched_at` in range, `runtime` known).
  final int episodeMinutes;

  /// Runtime of completed movies (`completed_at` in range, `runtime` known).
  final int movieMinutes;

  /// `false` when **no** runtime value was available at all — the UI then
  /// shows a hint instead of a misleading "0 min".
  final bool hasData;

  int get totalMinutes => episodeMinutes + movieMinutes;
}

/// Library-wide counts of the "overview" block.
class StatsOverview {
  const StatsOverview({
    required this.counts,
    required this.statusCounts,
    required this.statusCountsByKind,
  });

  /// Items per kind.
  final Map<MediaKind, int> counts;

  /// Items per status, across every kind.
  final Map<MediaStatus, int> statusCounts;

  /// Per kind, the number of items per status.
  final Map<MediaKind, Map<MediaStatus, int>> statusCountsByKind;

  int get total => counts.values.fold(0, (sum, value) => sum + value);

  bool get isEmpty => total == 0;

  int countOf(MediaKind kind) => counts[kind] ?? 0;

  int statusCount(MediaStatus status) => statusCounts[status] ?? 0;

  Map<MediaStatus, int> statusesFor(MediaKind kind) =>
      statusCountsByKind[kind] ?? const <MediaStatus, int>{};

  /// `completed / total` in percent (`0..100`) for [kind]; `0` when empty.
  ///
  /// Based on the stored `status` (that *is* the "is it done?" flag a user
  /// sees in the library), not on the presence of `completed_at`.
  double completionRate(MediaKind kind) {
    final total = countOf(kind);
    if (total == 0) return 0;
    final completed = statusesFor(kind)[MediaStatus.completed] ?? 0;
    return completed / total * 100;
  }
}

/// Everything the stats screen renders for one [StatsRange].
class StatsResult {
  const StatsResult({
    required this.overview,
    required this.completions,
    required this.watchTime,
    required this.pagesRead,
  });

  final StatsOverview overview;
  final CompletionsSeries completions;
  final WatchTimeStats watchTime;

  /// Sum of the signed `pages` from the reading log within the range — see
  /// [computePagesRead]. Negative values are possible (corrections).
  final int pagesRead;

  bool get isEmpty => overview.isEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// window helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Inclusive start of [range]'s window (first day of its earliest month).
///
/// `null` for [StatsRange.all] (unbounded).
DateTime? statsWindowStart(StatsRange range, DateTime now) {
  final months = range.months;
  if (months == null) return null;
  return DateTime(now.year, now.month - (months - 1), 1);
}

/// Exclusive end of [range]'s window — the first day of the month after [now].
DateTime statsWindowEnd(DateTime now) => DateTime(now.year, now.month + 1, 1);

/// The half-open `[start, end)` window of [range]; both `null` for all time.
({DateTime? start, DateTime? end}) statsWindow(StatsRange range, DateTime now) {
  if (range == StatsRange.all) return (start: null, end: null);
  return (start: statsWindowStart(range, now), end: statsWindowEnd(now));
}

bool _inWindow(DateTime? value, DateTime? start, DateTime? end) {
  if (value == null) return false;
  if (start != null && value.isBefore(start)) return false;
  if (end != null && !value.isBefore(end)) return false;
  return true;
}

/// A calendar day (no time), so DST hops cannot shift a timestamp into a
/// neighbouring month.
DateTime _dayOf(DateTime value) => DateTime(value.year, value.month, value.day);

/// Difference between two month-start dates, in months.
int _monthsBetween(DateTime firstMonth, DateTime lastMonth) =>
    (lastMonth.year - firstMonth.year) * 12 +
    (lastMonth.month - firstMonth.month);

// ─────────────────────────────────────────────────────────────────────────────
// overview (block 1)
// ─────────────────────────────────────────────────────────────────────────────

/// Counts [items] by kind and status.
StatsOverview computeOverview(List<MediaItem> items) {
  final counts = <MediaKind, int>{for (final kind in MediaKind.values) kind: 0};
  final statusCounts = <MediaStatus, int>{
    for (final status in MediaStatus.values) status: 0,
  };
  final byKind = <MediaKind, Map<MediaStatus, int>>{
    for (final kind in MediaKind.values)
      kind: <MediaStatus, int>{
        for (final status in MediaStatus.values) status: 0,
      },
  };

  for (final item in items) {
    counts[item.kind] = (counts[item.kind] ?? 0) + 1;
    statusCounts[item.status] = (statusCounts[item.status] ?? 0) + 1;
    final perKind = byKind[item.kind]!;
    perKind[item.status] = (perKind[item.status] ?? 0) + 1;
  }

  return StatsOverview(
    counts: counts,
    statusCounts: statusCounts,
    statusCountsByKind: byKind,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// completions over time (block 2.1)
// ─────────────────────────────────────────────────────────────────────────────

/// Buckets the completions of the range per month (or per year for a long
/// "all time" span).
///
/// * Movies / books: `completed_at`.
/// * Series: every episode with `watched_at` in the range counts as **one**.
/// * Empty buckets are kept so a quiet month shows as a gap.
///
/// For [StatsRange.all] the bucket size is derived from the **span of the
/// data**: monthly while it stays within 24 months, otherwise yearly. 24 is a
/// readability limit — beyond it a monthly axis on a phone turns into an
/// unreadable smear of 60+ bars.
CompletionsSeries computeCompletions({
  required List<MediaItem> items,
  required List<Episode> episodes,
  required StatsRange range,
  required DateTime now,
}) {
  final window = statsWindow(range, now);

  final movieDays = <DateTime>[];
  final bookDays = <DateTime>[];
  final episodeDays = <DateTime>[];

  for (final item in items) {
    final completed = item.completedAt;
    if (!_inWindow(completed, window.start, window.end)) continue;
    final day = _dayOf(completed!);
    if (item.kind == MediaKind.movie) {
      movieDays.add(day);
    } else if (item.kind == MediaKind.book) {
      bookDays.add(day);
    }
    // Series completions come from their episodes, never from the item.
  }

  for (final episode in episodes) {
    final watchedAt = episode.watchedAt;
    if (!episode.watched || !_inWindow(watchedAt, window.start, window.end)) {
      continue;
    }
    episodeDays.add(_dayOf(watchedAt!));
  }

  // ── fixed ranges: exactly one bucket per month of the window ──────────────
  final fixedStart = window.start;
  if (fixedStart != null) {
    final end = window.end!;
    final buckets = <StatsBucket>[];
    var cursor = DateTime(fixedStart.year, fixedStart.month, 1);
    final lastMonth = DateTime(end.year, end.month - 1, 1);
    while (!cursor.isAfter(lastMonth)) {
      buckets.add(
        StatsBucket(
          start: cursor,
          movies: _countInBucket(movieDays, cursor, BucketGranularity.month),
          books: _countInBucket(bookDays, cursor, BucketGranularity.month),
          episodes: _countInBucket(
            episodeDays,
            cursor,
            BucketGranularity.month,
          ),
        ),
      );
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return CompletionsSeries(
      buckets: buckets,
      granularity: BucketGranularity.month,
    );
  }

  // ── all time: derive the span from the data ───────────────────────────────
  final allDays = <DateTime>[...movieDays, ...bookDays, ...episodeDays];
  if (allDays.isEmpty) {
    return const CompletionsSeries(
      buckets: <StatsBucket>[],
      granularity: BucketGranularity.month,
    );
  }

  var earliest = allDays.first;
  var latest = allDays.first;
  for (final day in allDays) {
    if (day.isBefore(earliest)) earliest = day;
    if (day.isAfter(latest)) latest = day;
  }
  final firstMonth = DateTime(earliest.year, earliest.month, 1);
  final lastMonth = DateTime(latest.year, latest.month, 1);
  final spanMonths = _monthsBetween(firstMonth, lastMonth) + 1;

  final granularity = spanMonths <= 24
      ? BucketGranularity.month
      : BucketGranularity.year;

  final buckets = <StatsBucket>[];
  if (granularity == BucketGranularity.month) {
    var cursor = firstMonth;
    while (!cursor.isAfter(lastMonth)) {
      buckets.add(
        StatsBucket(
          start: cursor,
          movies: _countInBucket(movieDays, cursor, BucketGranularity.month),
          books: _countInBucket(bookDays, cursor, BucketGranularity.month),
          episodes: _countInBucket(
            episodeDays,
            cursor,
            BucketGranularity.month,
          ),
        ),
      );
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
  } else {
    var year = firstMonth.year;
    while (year <= lastMonth.year) {
      final cursor = DateTime(year, 1, 1);
      buckets.add(
        StatsBucket(
          start: cursor,
          granularity: BucketGranularity.year,
          movies: _countInBucket(movieDays, cursor, BucketGranularity.year),
          books: _countInBucket(bookDays, cursor, BucketGranularity.year),
          episodes: _countInBucket(episodeDays, cursor, BucketGranularity.year),
        ),
      );
      year++;
    }
  }

  return CompletionsSeries(buckets: buckets, granularity: granularity);
}

int _countInBucket(
  List<DateTime> days,
  DateTime bucketStart,
  BucketGranularity granularity,
) {
  if (granularity == BucketGranularity.month) {
    var count = 0;
    for (final day in days) {
      if (day.year == bucketStart.year && day.month == bucketStart.month) {
        count++;
      }
    }
    return count;
  }
  var count = 0;
  for (final day in days) {
    if (day.year == bucketStart.year) count++;
  }
  return count;
}

// ─────────────────────────────────────────────────────────────────────────────
// watch time (block 2.2)
// ─────────────────────────────────────────────────────────────────────────────

/// Sums the runtime of watched episodes plus completed movies in the range.
///
/// A missing runtime is **skipped** (never treated as `0`), and [hasData]
/// stays `false` when not a single runtime was available — the UI then shows a
/// hint rather than a fake "0 min".
WatchTimeStats computeWatchTime({
  required List<MediaItem> items,
  required List<Episode> episodes,
  required StatsRange range,
  required DateTime now,
}) {
  final window = statsWindow(range, now);
  var episodeMinutes = 0;
  var movieMinutes = 0;
  var dataPoints = 0;

  for (final item in items) {
    if (item.kind != MediaKind.movie) continue;
    if (!_inWindow(item.completedAt, window.start, window.end)) continue;
    final runtime = item.runtime;
    if (runtime == null) continue;
    movieMinutes += runtime;
    dataPoints++;
  }

  for (final episode in episodes) {
    if (!episode.watched) continue;
    if (!_inWindow(episode.watchedAt, window.start, window.end)) continue;
    final runtime = episode.runtime;
    if (runtime == null) continue;
    episodeMinutes += runtime;
    dataPoints++;
  }

  return WatchTimeStats(
    episodeMinutes: episodeMinutes,
    movieMinutes: movieMinutes,
    hasData: dataPoints > 0,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// pages (block 2.3)
// ─────────────────────────────────────────────────────────────────────────────

/// Sums the signed `pages` of every reading-log entry inside the range.
///
/// This is the exact figure the old approximation could not produce: each
/// entry is one commit of a book's page position (slider released, page
/// submitted, completion or reset), so partially read books contribute their
/// actual progress instead of nothing.
///
/// [ReadingLogEntry.pages] is **signed** (a correction downward is negative),
/// so the result may be negative in a period dominated by corrections — the
/// caller is expected to render that as-is rather than clamping it. Entries
/// without a `logged_at` are skipped, and an empty log yields `0`. The window
/// is the usual half-open `[start, end)`.
int computePagesRead({
  required List<ReadingLogEntry> log,
  required StatsRange range,
  required DateTime now,
}) {
  final window = statsWindow(range, now);
  var pages = 0;
  for (final entry in log) {
    if (!_inWindow(entry.loggedAt, window.start, window.end)) continue;
    pages += entry.pages;
  }
  return pages;
}

// ─────────────────────────────────────────────────────────────────────────────
// entry point
// ─────────────────────────────────────────────────────────────────────────────

/// Computes every number the stats screen needs for [range].
StatsResult computeStats({
  required List<MediaItem> items,
  required List<Episode> episodes,
  required List<ReadingLogEntry> log,
  required StatsRange range,
  required DateTime now,
}) {
  return StatsResult(
    overview: computeOverview(items),
    completions: computeCompletions(
      items: items,
      episodes: episodes,
      range: range,
      now: now,
    ),
    watchTime: computeWatchTime(
      items: items,
      episodes: episodes,
      range: range,
      now: now,
    ),
    pagesRead: computePagesRead(log: log, range: range, now: now),
  );
}

/// Stateful wrapper around [computeStats] with an injectable clock.
///
/// The screen holds one instance so tests can pin "now" and get deterministic
/// range boundaries.
class StatsCalculator {
  StatsCalculator({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// The reference "now" — the end of every relative range.
  DateTime get now => _clock();

  StatsResult calculate({
    required List<MediaItem> items,
    required List<Episode> episodes,
    required List<ReadingLogEntry> log,
    required StatsRange range,
  }) => computeStats(
    items: items,
    episodes: episodes,
    log: log,
    range: range,
    now: _clock(),
  );
}
