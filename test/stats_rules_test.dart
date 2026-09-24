import 'package:flutter_test/flutter_test.dart';

import 'package:media_tracker/models/episode.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/models/reading_log_entry.dart';
import 'package:media_tracker/services/stats_calculator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// builders
// ─────────────────────────────────────────────────────────────────────────────

/// Fixed reference "now": mid-June 2026. The 12-month window is then
/// 2025-07-01 (inclusive) … 2026-07-01 (exclusive).
final DateTime now = DateTime(2026, 6, 15, 12);

MediaItem _movie({
  String id = 'm1',
  MediaStatus status = MediaStatus.completed,
  DateTime? completedAt,
  int? runtime,
}) => MediaItem(
  id: id,
  kind: MediaKind.movie,
  title: 'Movie $id',
  status: status,
  completedAt: completedAt,
  runtime: runtime,
);

MediaItem _book({
  String id = 'b1',
  MediaStatus status = MediaStatus.completed,
  DateTime? completedAt,
  int? totalPages,
}) => MediaItem(
  id: id,
  kind: MediaKind.book,
  title: 'Book $id',
  status: status,
  completedAt: completedAt,
  totalPages: totalPages,
);

MediaItem _series({
  String id = 's1',
  MediaStatus status = MediaStatus.planned,
}) => MediaItem(
  id: id,
  kind: MediaKind.series,
  title: 'Series $id',
  status: status,
);

Episode _episode({
  String id = 'e1',
  String mediaItemId = 's1',
  int season = 1,
  int number = 1,
  bool watched = true,
  DateTime? watchedAt,
  int? runtime,
}) => Episode(
  id: id,
  mediaItemId: mediaItemId,
  seasonNumber: season,
  episodeNumber: number,
  watched: watched,
  watchedAt: watchedAt,
  runtime: runtime,
);

ReadingLogEntry _log({
  String id = 'l1',
  String mediaItemId = 'b1',
  required int pages,
  DateTime? loggedAt,
}) => ReadingLogEntry(
  id: id,
  mediaItemId: mediaItemId,
  pages: pages,
  loggedAt: loggedAt,
);

void main() {
  group('statsWindow', () {
    test('12 months spans the current month plus the previous eleven', () {
      final start = statsWindowStart(StatsRange.twelveMonths, now);
      expect(start, DateTime(2025, 7, 1));
      expect(statsWindowEnd(now), DateTime(2026, 7, 1));
    });

    test('1 month is only the current calendar month', () {
      expect(statsWindowStart(StatsRange.month, now), DateTime(2026, 6, 1));
    });

    test('6 months starts five months back', () {
      expect(statsWindowStart(StatsRange.sixMonths, now), DateTime(2026, 1, 1));
    });

    test('all time is unbounded', () {
      final window = statsWindow(StatsRange.all, now);
      expect(window.start, isNull);
      expect(window.end, isNull);
    });
  });

  group('computeOverview', () {
    test('counts every kind and splits by status', () {
      final overview = computeOverview([
        _movie(id: 'a', status: MediaStatus.completed),
        _movie(id: 'b', status: MediaStatus.dropped),
        _series(id: 'c', status: MediaStatus.inProgress),
        _book(id: 'd', status: MediaStatus.planned),
      ]);

      expect(overview.total, 4);
      expect(overview.countOf(MediaKind.movie), 2);
      expect(overview.countOf(MediaKind.series), 1);
      expect(overview.countOf(MediaKind.book), 1);

      expect(overview.statusCount(MediaStatus.completed), 1);
      expect(overview.statusCount(MediaStatus.dropped), 1);
      expect(overview.statusCount(MediaStatus.inProgress), 1);
      expect(overview.statusCount(MediaStatus.planned), 1);

      // Per-kind breakdown.
      expect(overview.statusesFor(MediaKind.movie)[MediaStatus.completed], 1);
      expect(overview.statusesFor(MediaKind.movie)[MediaStatus.dropped], 1);
      expect(overview.statusesFor(MediaKind.book)[MediaStatus.planned], 1);
    });

    test('completion rate is completed / total per kind', () {
      final overview = computeOverview([
        _movie(id: 'a', status: MediaStatus.completed),
        _movie(id: 'b', status: MediaStatus.planned),
        _book(id: 'c', status: MediaStatus.completed),
        _book(id: 'd', status: MediaStatus.completed),
      ]);

      expect(overview.completionRate(MediaKind.movie), 50);
      expect(overview.completionRate(MediaKind.book), 100);
      // A kind with no items is 0, never a divide-by-zero.
      expect(overview.completionRate(MediaKind.series), 0);
    });

    test('an empty library has no counts and is empty', () {
      final overview = computeOverview(const <MediaItem>[]);
      expect(overview.isEmpty, isTrue);
      expect(overview.total, 0);
      for (final kind in MediaKind.values) {
        expect(overview.countOf(kind), 0);
        expect(overview.completionRate(kind), 0);
      }
    });
  });

  group('computeCompletions', () {
    test('movies and books count by completed_at, series episodes by '
        'watched_at', () {
      final series = computeCompletions(
        items: [
          _movie(id: 'a', completedAt: DateTime(2026, 6, 3)),
          _book(id: 'b', completedAt: DateTime(2026, 6, 5), totalPages: 100),
        ],
        episodes: [
          _episode(id: 'e1', watchedAt: DateTime(2026, 6, 5, 20)),
          _episode(id: 'e2', number: 2, watchedAt: DateTime(2026, 6, 6)),
        ],
        range: StatsRange.month,
        now: now,
      );

      expect(series.granularity, BucketGranularity.month);
      expect(series.buckets, hasLength(1));
      final june = series.buckets.single;
      expect(june.start, DateTime(2026, 6, 1));
      expect(june.movies, 1);
      expect(june.books, 1);
      // Each watched episode counts as one.
      expect(june.episodes, 2);
      expect(june.total, 4);
    });

    test('a series item itself never contributes a completion', () {
      // Even the series row carries a completed_at (derived state) — the
      // episode list is the source of truth for series.
      final series = computeCompletions(
        items: [
          _series(
            status: MediaStatus.completed,
          ).copyWith(completedAt: DateTime(2026, 6, 10)),
        ],
        episodes: const <Episode>[],
        range: StatsRange.month,
        now: now,
      );
      expect(series.buckets.single.total, 0);
    });

    test('unwatched episodes and episodes without a timestamp are ignored', () {
      final series = computeCompletions(
        items: const <MediaItem>[],
        episodes: [
          _episode(id: 'e1', watched: false, watchedAt: DateTime(2026, 6, 2)),
          _episode(id: 'e2', watched: true, watchedAt: null),
          _episode(id: 'e3', watched: true, watchedAt: DateTime(2026, 6, 4)),
        ],
        range: StatsRange.month,
        now: now,
      );
      expect(series.buckets.single.episodes, 1);
    });

    test('12 months produces one bucket per month, empty ones included', () {
      final series = computeCompletions(
        items: [
          _movie(id: 'a', completedAt: DateTime(2025, 7, 1)), // first month
          _movie(id: 'b', completedAt: DateTime(2026, 6, 30, 23, 59)), // last
        ],
        episodes: const <Episode>[],
        range: StatsRange.twelveMonths,
        now: now,
      );

      expect(series.buckets, hasLength(12));
      expect(series.buckets.first.start, DateTime(2025, 7, 1));
      expect(series.buckets.last.start, DateTime(2026, 6, 1));

      // Everything between the two data points is an explicit zero.
      expect(series.buckets.first.movies, 1);
      expect(series.buckets.last.movies, 1);
      for (final bucket in series.buckets.skip(1).take(10)) {
        expect(bucket.total, 0);
        expect(bucket.isEmpty, isTrue);
      }
      expect(series.maxTotal, 1);
    });

    test('boundaries are half-open: start counts, end does not', () {
      final atStart = DateTime(2025, 7, 1); // == window start
      final beforeStart = DateTime(2025, 6, 30, 23, 59, 59);
      final atEnd = DateTime(2026, 7, 1); // == window end (exclusive)

      final series = computeCompletions(
        items: [
          _movie(id: 'start', completedAt: atStart),
          _movie(id: 'before', completedAt: beforeStart),
          _movie(id: 'end', completedAt: atEnd),
        ],
        episodes: const <Episode>[],
        range: StatsRange.twelveMonths,
        now: now,
      );

      final total = series.buckets.fold(0, (sum, b) => sum + b.total);
      expect(total, 1);
      expect(series.buckets.first.start, atStart);
    });

    test('1-month range only sees the current month', () {
      final items = [
        _movie(id: 'june', completedAt: DateTime(2026, 6, 5)),
        _movie(id: 'may', completedAt: DateTime(2026, 5, 20)),
      ];
      final month = computeCompletions(
        items: items,
        episodes: const <Episode>[],
        range: StatsRange.month,
        now: now,
      );
      final twelve = computeCompletions(
        items: items,
        episodes: const <Episode>[],
        range: StatsRange.twelveMonths,
        now: now,
      );

      expect(month.buckets, hasLength(1));
      expect(month.buckets.single.total, 1);
      expect(twelve.buckets.fold(0, (sum, b) => sum + b.total), 2);
    });

    test('all time is monthly while the data span stays within 24 months', () {
      final series = computeCompletions(
        items: [
          _movie(id: 'a', completedAt: DateTime(2025, 1, 10)),
          _movie(id: 'b', completedAt: DateTime(2026, 6, 10)),
        ],
        episodes: const <Episode>[],
        range: StatsRange.all,
        now: now,
      );

      expect(series.granularity, BucketGranularity.month);
      // Jan 2025 … Jun 2026 inclusive = 18 buckets.
      expect(series.buckets, hasLength(18));
      expect(series.buckets.first.start, DateTime(2025, 1, 1));
      expect(series.buckets.last.start, DateTime(2026, 6, 1));
    });

    test('all time switches to yearly past 24 months', () {
      final series = computeCompletions(
        items: [
          _movie(id: 'a', completedAt: DateTime(2000, 1, 10)),
          _movie(id: 'b', completedAt: DateTime(2026, 6, 10)),
        ],
        episodes: const <Episode>[],
        range: StatsRange.all,
        now: now,
      );

      expect(series.granularity, BucketGranularity.year);
      expect(series.buckets, hasLength(27)); // 2000 … 2026
      expect(series.buckets.first.start, DateTime(2000, 1, 1));
      expect(series.buckets.last.start, DateTime(2026, 1, 1));
      expect(series.buckets.first.movies, 1);
      expect(series.buckets.last.movies, 1);
      expect(series.buckets[1].isEmpty, isTrue);
    });

    test('an empty range has zeroed buckets, an empty library none', () {
      final emptyRange = computeCompletions(
        items: [_movie(id: 'a', completedAt: DateTime(2026, 6, 5))],
        episodes: const <Episode>[],
        range: StatsRange.month,
        now: DateTime(2026, 8, 15),
      );
      expect(emptyRange.buckets, hasLength(1));
      expect(emptyRange.isEmpty, isTrue);

      final emptyLibrary = computeCompletions(
        items: const <MediaItem>[],
        episodes: const <Episode>[],
        range: StatsRange.all,
        now: now,
      );
      expect(emptyLibrary.buckets, isEmpty);
      expect(emptyLibrary.isEmpty, isTrue);
    });
  });

  group('computeWatchTime', () {
    test('adds watched episodes and completed movies', () {
      final stats = computeWatchTime(
        items: [
          _movie(id: 'a', completedAt: DateTime(2026, 6, 2), runtime: 120),
        ],
        episodes: [
          _episode(id: 'e1', watchedAt: DateTime(2026, 6, 3), runtime: 45),
          _episode(
            id: 'e2',
            number: 2,
            watchedAt: DateTime(2026, 6, 4),
            runtime: 50,
          ),
        ],
        range: StatsRange.month,
        now: now,
      );

      expect(stats.movieMinutes, 120);
      expect(stats.episodeMinutes, 95);
      expect(stats.totalMinutes, 215);
      expect(stats.hasData, isTrue);
    });

    test('missing runtimes are skipped, not counted as zero', () {
      final stats = computeWatchTime(
        items: [
          _movie(id: 'a', completedAt: DateTime(2026, 6, 2), runtime: null),
        ],
        episodes: [
          _episode(id: 'e1', watchedAt: DateTime(2026, 6, 3), runtime: null),
        ],
        range: StatsRange.month,
        now: now,
      );

      expect(stats.totalMinutes, 0);
      // No runtime value at all → the UI must show a hint, not "0 min".
      expect(stats.hasData, isFalse);
    });

    test('only in-range completions and watched episodes contribute', () {
      final stats = computeWatchTime(
        items: [
          _movie(id: 'in', completedAt: DateTime(2026, 6, 2), runtime: 100),
          _movie(id: 'out', completedAt: DateTime(2026, 5, 2), runtime: 999),
          // Not completed → ignored even with a runtime.
          _movie(id: 'planned', runtime: 500),
        ],
        episodes: [
          _episode(id: 'e1', watchedAt: DateTime(2026, 6, 3), runtime: 30),
          _episode(
            id: 'e2',
            watched: false,
            watchedAt: DateTime(2026, 6, 3),
            runtime: 999,
          ),
          _episode(id: 'e3', watchedAt: null, runtime: 999),
        ],
        range: StatsRange.month,
        now: now,
      );

      expect(stats.movieMinutes, 100);
      expect(stats.episodeMinutes, 30);
    });

    test('all time sums everything', () {
      final stats = computeWatchTime(
        items: [
          _movie(id: 'old', completedAt: DateTime(2010, 1, 1), runtime: 90),
          _movie(id: 'new', completedAt: DateTime(2026, 6, 1), runtime: 10),
        ],
        episodes: const <Episode>[],
        range: StatsRange.all,
        now: now,
      );
      expect(stats.totalMinutes, 100);
    });
  });

  group('computePagesRead', () {
    test('sums the reading log entries inside the range', () {
      final pages = computePagesRead(
        log: [
          _log(id: 'a', pages: 120, loggedAt: DateTime(2026, 6, 2)),
          _log(id: 'b', pages: 80, loggedAt: DateTime(2026, 6, 9)),
        ],
        range: StatsRange.month,
        now: now,
      );
      expect(pages, 200);
    });

    test('partial reads count; out-of-range entries do not', () {
      final pages = computePagesRead(
        log: [
          // A partially read book contributes its actual progress — the whole
          // point of the reading log (the old approximation would miss it).
          _log(id: 'in', pages: 40, loggedAt: DateTime(2026, 6, 3)),
          _log(id: 'old', pages: 999, loggedAt: DateTime(2025, 1, 1)),
        ],
        range: StatsRange.month,
        now: now,
      );
      expect(pages, 40);
    });

    test('corrections subtract and can make the total negative', () {
      final pages = computePagesRead(
        log: [
          _log(id: 'read', pages: 30, loggedAt: DateTime(2026, 6, 4)),
          _log(id: 'fix', pages: -50, loggedAt: DateTime(2026, 6, 5)),
        ],
        range: StatsRange.month,
        now: now,
      );
      expect(pages, -20);
    });

    test('an empty log yields zero', () {
      expect(
        computePagesRead(
          log: const <ReadingLogEntry>[],
          range: StatsRange.all,
          now: now,
        ),
        0,
      );
      expect(
        computePagesRead(
          log: const <ReadingLogEntry>[],
          range: StatsRange.month,
          now: now,
        ),
        0,
      );
    });

    test('the window is half-open: start counts, end does not', () {
      final pages = computePagesRead(
        log: [
          _log(id: 'start', pages: 10, loggedAt: DateTime(2025, 7, 1)),
          _log(
            id: 'before',
            pages: 999,
            loggedAt: DateTime(2025, 6, 30, 23, 59, 59),
          ),
          _log(id: 'end', pages: 999, loggedAt: DateTime(2026, 7, 1)),
        ],
        range: StatsRange.twelveMonths,
        now: now,
      );
      expect(pages, 10);
    });

    test('entries without a timestamp are skipped, never crash', () {
      final pages = computePagesRead(
        log: [_log(id: 'no-time', pages: 100, loggedAt: null)],
        range: StatsRange.all,
        now: now,
      );
      expect(pages, 0);
    });

    test('all time sums the whole log', () {
      final pages = computePagesRead(
        log: [
          _log(id: 'a', pages: 100, loggedAt: DateTime(2010, 1, 1)),
          _log(id: 'b', pages: 25, loggedAt: DateTime(2026, 6, 1)),
        ],
        range: StatsRange.all,
        now: now,
      );
      expect(pages, 125);
    });
  });

  group('computeStats / StatsCalculator', () {
    test('bundles every metric for the given range', () {
      final result = computeStats(
        items: [
          _movie(id: 'a', completedAt: DateTime(2026, 6, 2), runtime: 100),
          _book(id: 'b', completedAt: DateTime(2026, 6, 3), totalPages: 250),
        ],
        episodes: [
          _episode(id: 'e1', watchedAt: DateTime(2026, 6, 4), runtime: 40),
        ],
        log: [_log(id: 'l1', pages: 250, loggedAt: DateTime(2026, 6, 3))],
        range: StatsRange.month,
        now: now,
      );

      expect(result.isEmpty, isFalse);
      expect(result.overview.total, 2);
      expect(result.completions.buckets.single.total, 3);
      expect(result.watchTime.totalMinutes, 140);
      expect(result.pagesRead, 250);
    });

    test('pages come from the log, not from completed books', () {
      // A completed 400-page book with no log entry contributes nothing…
      final result = computeStats(
        items: [
          _book(id: 'b', completedAt: DateTime(2026, 6, 3), totalPages: 400),
        ],
        episodes: const <Episode>[],
        log: [_log(id: 'l1', pages: 12, loggedAt: DateTime(2026, 6, 10))],
        range: StatsRange.month,
        now: now,
      );
      // …and a partially read book is reflected by its log entries.
      expect(result.pagesRead, 12);
    });

    test('the injected clock drives the range window', () {
      final items = [
        _movie(id: 'a', completedAt: DateTime(2026, 6, 2), runtime: 100),
      ];
      // Calculator pinned to June 2026…
      final june = StatsCalculator(clock: () => now);
      expect(
        june
            .calculate(
              items: items,
              episodes: const <Episode>[],
              log: const <ReadingLogEntry>[],
              range: StatsRange.month,
            )
            .watchTime
            .totalMinutes,
        100,
      );

      // …and to August 2026, where the June completion is out of range.
      final august = StatsCalculator(clock: () => DateTime(2026, 8, 1));
      expect(
        august
            .calculate(
              items: items,
              episodes: const <Episode>[],
              log: const <ReadingLogEntry>[],
              range: StatsRange.month,
            )
            .watchTime
            .hasData,
        isFalse,
      );
    });
  });
}
