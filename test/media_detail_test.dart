import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/main.dart';
import 'package:media_tracker/models/episode.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/models/reading_log_entry.dart';
import 'package:media_tracker/models/tmdb_result.dart';
import 'package:media_tracker/providers/auth_provider.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/providers/theme_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/screens/media_detail_screen.dart';
import 'package:media_tracker/services/tmdb_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// fakes
// ─────────────────────────────────────────────────────────────────────────────

/// Always signed in — no Supabase backend needed.
class _FakeAuth extends AuthProvider {
  @override
  AuthStatus get status => AuthStatus.signedIn;

  @override
  String? get email => 'me@example.com';

  @override
  Future<String?> sendMagicLink(String email) async => null;

  @override
  Future<void> signOut() async {}
}

/// Metadata client stub — no network.
class _StubTmdb extends TmdbClient {
  _StubTmdb()
    : super(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        token: 'fake',
      );
}

/// Series metadata stub for the Phase 3b episode tests — no network.
///
/// [episodesBySeason] maps a season number to its episode count (season `0`
/// may be included to prove that specials are skipped). [failSeasons] makes
/// the matching `fetchSeason` throw.
class _SeriesTmdb extends TmdbClient {
  _SeriesTmdb({
    this.episodesBySeason = const <int, int>{1: 4},
    this.failSeasons = const <int>{},
    this.failTv = false,
  }) : super(
         httpClient: MockClient((_) async => http.Response('{}', 200)),
         token: 'fake',
       );

  final Map<int, int> episodesBySeason;
  final Set<int> failSeasons;

  /// Mutable so a retry test can let the second attempt succeed.
  bool failTv;

  int fetchTvCount = 0;
  final List<int> requestedSeasons = <int>[];
  final List<String> languages = <String>[];

  @override
  Future<TmdbTvDetails> fetchTv(int id, {String? language}) async {
    fetchTvCount++;
    languages.add(language ?? '<none>');
    if (failTv) throw const TmdbException('TMDB request failed.');
    final seasons = episodesBySeason.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return TmdbTvDetails(
      id: id,
      name: 'Lost',
      originalName: 'Lost',
      year: 2004,
      numberOfSeasons: episodesBySeason.length,
      numberOfEpisodes: episodesBySeason.values.fold<int>(0, (a, b) => a + b),
      seasons: [
        for (final entry in seasons)
          TmdbSeasonSummary(
            seasonNumber: entry.key,
            name: 'Season ${entry.key}',
            episodeCount: entry.value,
          ),
      ],
    );
  }

  @override
  Future<TmdbSeasonDetails> fetchSeason(
    int tvId,
    int seasonNumber, {
    String? language,
  }) async {
    requestedSeasons.add(seasonNumber);
    languages.add(language ?? '<none>');
    if (failSeasons.contains(seasonNumber)) {
      throw const TmdbException('TMDB request failed.');
    }
    final count = episodesBySeason[seasonNumber] ?? 0;
    return TmdbSeasonDetails(
      seasonNumber: seasonNumber,
      name: 'Season $seasonNumber',
      episodes: [
        for (var i = 1; i <= count; i++)
          TmdbEpisode(
            episodeNumber: i,
            name: 'Pilot $i',
            airDate: DateTime.utc(2004, 9, i),
            runtime: 42,
          ),
      ],
    );
  }
}

/// Repository stub: an in-memory library that applies tracking writes like
/// PostgREST would and records them, plus an in-memory episode store.
class _FakeRepo extends MediaRepository {
  _FakeRepo(this.items, {List<Episode> episodes = const <Episode>[]})
    : episodes = List<Episode>.of(episodes);

  List<MediaItem> items;
  List<Episode> episodes;

  final List<Map<String, dynamic>> writes = [];
  final List<String> deleted = [];

  /// Payloads written to the reading log.
  final List<Map<String, dynamic>> logs = [];
  int episodeFetchCount = 0;

  @override
  Future<List<MediaItem>> fetchAll() async => List<MediaItem>.of(items);

  @override
  Future<MediaItem> updateTracking(
    String id,
    Map<String, dynamic> fields,
  ) async {
    writes.add(fields);
    final index = items.indexWhere((item) => item.id == id);
    final row = Map<String, dynamic>.from(items[index].toMap())..addAll(fields);
    final updated = MediaItem.fromMap(row);
    items[index] = updated;
    return updated;
  }

  @override
  Future<ReadingLogEntry> insertReadingLog({
    required String mediaItemId,
    required int pages,
    DateTime? loggedAt,
  }) async {
    logs.add(<String, dynamic>{'media_item_id': mediaItemId, 'pages': pages});
    return ReadingLogEntry(
      mediaItemId: mediaItemId,
      pages: pages,
      loggedAt: loggedAt,
    );
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    items.removeWhere((item) => item.id == id);
  }

  // ── episodes ──────────────────────────────────────────────────────────────

  @override
  Future<List<Episode>> fetchEpisodes(String mediaItemId) async {
    episodeFetchCount++;
    return episodes
        .where((episode) => episode.mediaItemId == mediaItemId)
        .toList()
      ..sort((a, b) {
        final bySeason = a.seasonNumber.compareTo(b.seasonNumber);
        return bySeason != 0
            ? bySeason
            : a.episodeNumber.compareTo(b.episodeNumber);
      });
  }

  @override
  Future<List<Episode>> upsertEpisodeMetadata(List<Episode> incoming) async {
    final saved = <Episode>[];
    for (final episode in incoming) {
      final index = episodes.indexWhere(
        (candidate) =>
            candidate.mediaItemId == episode.mediaItemId &&
            candidate.seasonNumber == episode.seasonNumber &&
            candidate.episodeNumber == episode.episodeNumber,
      );
      final stored = index == -1
          ? episode.copyWith(
              id:
                  episode.id ??
                  'ep-${episode.seasonNumber}-${episode.episodeNumber}',
            )
          : episode.copyWith(
              id: episodes[index].id,
              // The watch state of an existing row is never touched.
              watched: episodes[index].watched,
              watchedAt: episodes[index].watchedAt,
              createdAt: episodes[index].createdAt,
            );
      if (index == -1) {
        episodes.add(stored);
      } else {
        episodes[index] = stored;
      }
      saved.add(stored);
    }
    return saved;
  }

  @override
  Future<List<Episode>> upsertEpisodes(List<Episode> incoming) =>
      upsertEpisodeMetadata(incoming);

  @override
  Future<Episode> setWatched(String episodeId, bool watched) async {
    final index = episodes.indexWhere((episode) => episode.id == episodeId);
    final updated = _copyWatched(episodes[index], watched);
    episodes[index] = updated;
    return updated;
  }

  @override
  Future<List<Episode>> markSeasonWatched(
    String mediaItemId,
    int seasonNumber,
  ) async => _setSeason(mediaItemId, seasonNumber, watched: true);

  @override
  Future<List<Episode>> resetSeason(
    String mediaItemId,
    int seasonNumber,
  ) async => _setSeason(mediaItemId, seasonNumber, watched: false);

  List<Episode> _setSeason(
    String mediaItemId,
    int seasonNumber, {
    required bool watched,
  }) {
    final updated = <Episode>[];
    for (var i = 0; i < episodes.length; i++) {
      final episode = episodes[i];
      if (episode.mediaItemId != mediaItemId ||
          episode.seasonNumber != seasonNumber) {
        continue;
      }
      final next = _copyWatched(episode, watched);
      episodes[i] = next;
      updated.add(next);
    }
    return updated;
  }

  Episode _copyWatched(Episode episode, bool watched) => Episode(
    id: episode.id,
    mediaItemId: episode.mediaItemId,
    seasonNumber: episode.seasonNumber,
    episodeNumber: episode.episodeNumber,
    name: episode.name,
    overview: episode.overview,
    airDate: episode.airDate,
    stillUrl: episode.stillUrl,
    runtime: episode.runtime,
    watched: watched,
    watchedAt: watched ? DateTime.utc(2026, 1, 1) : null,
    createdAt: episode.createdAt,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// helpers
// ─────────────────────────────────────────────────────────────────────────────

MediaItem _movie({
  String id = 'movie-1',
  String title = 'Inception',
  MediaStatus status = MediaStatus.planned,
  double? percent,
  DateTime? startedAt,
  DateTime? completedAt,
  String? overview = 'A thief who steals corporate secrets.',
}) => MediaItem(
  id: id,
  kind: MediaKind.movie,
  title: title,
  releaseYear: 2010,
  overview: overview,
  status: status,
  progressPercent: percent,
  startedAt: startedAt,
  completedAt: completedAt,
);

MediaItem _book({
  String id = 'book-1',
  String title = 'Dune',
  int? totalPages,
  List<String> authors = const ['Frank Herbert'],
  double? percent,
  int? current,
}) => MediaItem(
  id: id,
  kind: MediaKind.book,
  title: title,
  releaseYear: 1965,
  overview: 'A desert planet.',
  authors: authors,
  totalPages: totalPages,
  status: MediaStatus.inProgress,
  progressPercent: percent,
  progressCurrent: current,
);

MediaItem _series({
  String id = 'series-1',
  String title = 'Lost',
  MediaStatus status = MediaStatus.planned,
  double? percent,
  int? totalSeasons = 6,
  int? totalEpisodes = 121,
  String? externalId,
}) => MediaItem(
  id: id,
  kind: MediaKind.series,
  title: title,
  releaseYear: 2004,
  overview: 'Stranded on an island.',
  totalSeasons: totalSeasons,
  totalEpisodes: totalEpisodes,
  status: status,
  progressPercent: percent,
  externalSource: externalId == null ? null : 'tmdb',
  externalId: externalId,
);

/// Seeds [count] episodes of [seasonNumber] for [mediaItemId].
///
/// [overview] and [stillUrl] are applied to every seeded episode (used by the
/// episode-description tests); both default to `null`.
List<Episode> _episodes(
  String mediaItemId, {
  int seasonNumber = 1,
  int count = 4,
  int watched = 0,
  String? overview,
  String? stillUrl,
}) => [
  for (var i = 1; i <= count; i++)
    Episode(
      id: 'ep-$seasonNumber-$i',
      mediaItemId: mediaItemId,
      seasonNumber: seasonNumber,
      episodeNumber: i,
      name: 'Episode $i',
      overview: overview,
      airDate: DateTime.utc(2004, 9, i),
      stillUrl: stillUrl,
      runtime: 42,
      watched: i <= watched,
      watchedAt: i <= watched ? DateTime.utc(2026, 1, 1) : null,
    ),
];

/// Opens the app on a tall surface so the whole detail view fits without
/// scrolling, then taps the entry with [title].
Future<void> _openDetail(
  WidgetTester tester, {
  required List<MediaItem> items,
  required String title,
  AppLanguage language = AppLanguage.en,
  MediaRepository? repository,
  TmdbClient? tmdb,
}) async {
  tester.view.physicalSize = const Size(1100, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaTrackerApp(
      themeProvider: ThemeProvider(),
      // English by default so the assertions stay readable; the app default is
      // German (covered by the dedicated tests below).
      settingsProvider: SettingsProvider(initial: language),
      authProvider: _FakeAuth(),
      repository: repository ?? _FakeRepo(items),
      tmdbClient: tmdb ?? _StubTmdb(),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();

  expect(find.byType(MediaDetailScreen), findsOneWidget);
}

/// A finder scoped to the pushed detail screen (the library list behind it may
/// contain the same texts).
Finder inDetail(Finder matching) =>
    find.descendant(of: find.byType(MediaDetailScreen), matching: matching);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // ───────────────────────────────────────────────────────────────────────────
  // library list
  // ───────────────────────────────────────────────────────────────────────────

  group('library list', () {
    testWidgets('shows a status badge and progress for every kind', (
      tester,
    ) async {
      await _pumpLibrary(
        tester,
        items: [
          _movie(percent: 40),
          _book(totalPages: 300, percent: 50, current: 150),
          _series(percent: 60),
        ],
      );

      // A progress bar per row — including the series (derived episode
      // progress is persisted on media_items since phase 3b).
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      // Status badges are rendered per row.
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Planned'), findsNWidgets(2));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // detail screen
  // ───────────────────────────────────────────────────────────────────────────

  group('movie detail', () {
    testWidgets('tapping a row opens the detail with metadata', (tester) async {
      await _openDetail(
        tester,
        items: [_movie(status: MediaStatus.inProgress, percent: 40)],
        title: 'Inception',
      );

      expect(inDetail(find.text('Inception')), findsOneWidget);
      expect(inDetail(find.text('2010')), findsOneWidget);
      // The AppBar title and the header badge both name the kind.
      expect(inDetail(find.text('Movie')), findsWidgets);
      expect(
        inDetail(find.text('A thief who steals corporate secrets.')),
        findsOneWidget,
      );
      // A movie gets the percent slider, no page input.
      expect(find.byKey(MediaDetailScreen.percentSliderKey), findsOneWidget);
      expect(find.byKey(MediaDetailScreen.pageFieldKey), findsNothing);
    });

    testWidgets('changing the status persists it immediately', (tester) async {
      final repository = _FakeRepo([_movie()]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Inception',
        repository: repository,
      );

      await tester.tap(inDetail(find.text('In progress')));
      await tester.pumpAndSettle();

      expect(repository.writes.single['status'], 'in_progress');
      // The badge in the header switched over too.
      expect(inDetail(find.text('In progress')), findsWidgets);
    });

    testWidgets('dragging the percent slider to 100 % completes the item', (
      tester,
    ) async {
      final repository = _FakeRepo([
        _movie(status: MediaStatus.inProgress, percent: 40),
      ]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Inception',
        repository: repository,
      );

      await tester.drag(
        find.byKey(MediaDetailScreen.percentSliderKey),
        const Offset(1000, 0),
      );
      await tester.pumpAndSettle();

      expect(repository.writes.last['progress_percent'], 100);
      expect(repository.writes.last['status'], 'completed');
      expect(inDetail(find.text('Completed')), findsWidgets);
    });

    testWidgets('editing started_at opens the pickers and stores the value', (
      tester,
    ) async {
      final repository = _FakeRepo([_movie()]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Inception',
        repository: repository,
      );

      expect(inDetail(find.text('Not set yet')), findsNWidgets(2));

      await tester.tap(find.byKey(MediaDetailScreen.editStartedAtKey));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(repository.writes.last.containsKey('started_at'), isTrue);
      expect(repository.writes.last['started_at'], isNotNull);
      // The placeholder is replaced by the formatted timestamp.
      expect(inDetail(find.text('Not set yet')), findsOneWidget);
    });
  });

  group('book detail', () {
    testWidgets('page input is converted to a percent value', (tester) async {
      final repository = _FakeRepo([_book(totalPages: 300)]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Dune',
        repository: repository,
      );

      expect(inDetail(find.text('by Frank Herbert')), findsOneWidget);
      expect(inDetail(find.text('300 pages')), findsOneWidget);
      expect(find.byKey(MediaDetailScreen.pageSliderKey), findsOneWidget);
      expect(find.byKey(MediaDetailScreen.pageFieldKey), findsOneWidget);
      expect(find.byKey(MediaDetailScreen.percentSliderKey), findsNothing);

      await tester.enterText(find.byKey(MediaDetailScreen.pageFieldKey), '150');
      await tester.tap(find.byKey(MediaDetailScreen.savePageButtonKey));
      await tester.pumpAndSettle();

      expect(repository.writes.last['progress_current'], 150);
      expect(repository.writes.last['progress_percent'], 50);
      expect(inDetail(find.text('50%')), findsWidgets);
    });

    testWidgets('releasing the page slider logs exactly one reading entry', (
      tester,
    ) async {
      final repository = _FakeRepo([_book(totalPages: 300, current: 0)]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Dune',
        repository: repository,
      );

      // A drag fires `onChanged` many times; only the release persists — and
      // only that single write reaches the reading log (no mini entries).
      await tester.drag(
        find.byKey(MediaDetailScreen.pageSliderKey),
        const Offset(500, 0),
      );
      await tester.pumpAndSettle();

      expect(repository.writes, hasLength(1));
      expect(repository.logs, hasLength(1));
      expect(repository.logs.single['pages'], greaterThan(0));
    });

    testWidgets('completing from the detail logs the remaining pages', (
      tester,
    ) async {
      final repository = _FakeRepo([_book(totalPages: 300, current: 100)]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Dune',
        repository: repository,
      );

      await tester.tap(inDetail(find.text('Completed')));
      await tester.pumpAndSettle();

      // 300 pages, 100 already read → the last 200 are logged.
      expect(repository.logs.single['pages'], 200);
    });

    testWidgets('a book without a page count writes no reading entry', (
      tester,
    ) async {
      final repository = _FakeRepo([_book(percent: 10)]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Dune',
        repository: repository,
      );

      await tester.drag(
        find.byKey(MediaDetailScreen.percentSliderKey),
        const Offset(200, 0),
      );
      await tester.pumpAndSettle();

      expect(repository.logs, isEmpty);
    });

    testWidgets(
      'a book without a page count falls back to the percent slider',
      (tester) async {
        await _openDetail(tester, items: [_book()], title: 'Dune');

        expect(find.byKey(MediaDetailScreen.percentSliderKey), findsOneWidget);
        expect(find.byKey(MediaDetailScreen.pageSliderKey), findsNothing);
        // The total page count stays editable.
        expect(
          find.byKey(MediaDetailScreen.totalPagesFieldKey),
          findsOneWidget,
        );
      },
    );

    testWidgets('the total page count can be filled in later', (tester) async {
      final repository = _FakeRepo([_book()]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Dune',
        repository: repository,
      );

      await tester.enterText(
        find.byKey(MediaDetailScreen.totalPagesFieldKey),
        '250',
      );
      await tester.tap(find.byKey(MediaDetailScreen.saveTotalPagesButtonKey));
      await tester.pumpAndSettle();

      expect(repository.writes.last['total_pages'], 250);
      // Once the page count is known the page slider takes over.
      expect(find.byKey(MediaDetailScreen.pageSliderKey), findsOneWidget);
      expect(find.byKey(MediaDetailScreen.percentSliderKey), findsNothing);
    });
  });

  group('series detail (phase 3b)', () {
    testWidgets('loads episodes lazily from TMDB and skips specials', (
      tester,
    ) async {
      final repository = _FakeRepo([_series(externalId: '95396')]);
      final tmdb = _SeriesTmdb(episodesBySeason: {0: 3, 1: 4});
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
        tmdb: tmdb,
      );

      // Season 1 only — the specials season (0) is never requested.
      expect(tmdb.fetchTvCount, 1);
      expect(tmdb.requestedSeasons, <int>[1]);
      // The fetched episodes were persisted (metadata-only upsert).
      expect(repository.episodes, hasLength(4));
      // The season selector and the episode list are rendered.
      expect(inDetail(find.text('Season 1')), findsOneWidget);
      expect(inDetail(find.text('Episode 1 · Pilot 1')), findsOneWidget);
      // No manual status selector / movie-book controls for series.
      expect(find.byType(SegmentedButton<MediaStatus>), findsNothing);
      expect(find.byKey(MediaDetailScreen.percentSliderKey), findsNothing);
      expect(find.byKey(MediaDetailScreen.pageSliderKey), findsNothing);
      // …but the screen stays usable.
      expect(inDetail(find.text('Series')), findsWidgets);
      expect(find.byKey(MediaDetailScreen.deleteButtonKey), findsOneWidget);
    });

    testWidgets('a second open reuses the cached episodes', (tester) async {
      final repository = _FakeRepo([_series(externalId: '95396')]);
      final tmdb = _SeriesTmdb();
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
        tmdb: tmdb,
      );
      expect(tmdb.fetchTvCount, 1);
      expect(repository.episodeFetchCount, 1);

      // Back to the library, then open the same series again.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lost').first);
      await tester.pumpAndSettle();

      // No second TMDB request, no second database read.
      expect(tmdb.fetchTvCount, 1);
      expect(repository.episodeFetchCount, 1);
      expect(inDetail(find.text('Season 1')), findsOneWidget);
    });

    testWidgets('checking an episode derives the progress and status', (
      tester,
    ) async {
      final repository = _FakeRepo([
        _series(),
      ], episodes: _episodes('series-1'));
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
      );

      expect(inDetail(find.text('0 of 4 episodes')), findsOneWidget);
      await tester.tap(find.byKey(MediaDetailScreen.episodeCheckboxKey(1, 1)));
      await tester.pumpAndSettle();

      expect(repository.writes.last['progress_percent'], 25);
      expect(repository.writes.last['status'], 'in_progress');
      expect(inDetail(find.text('25%')), findsWidgets);
      expect(inDetail(find.text('1 of 4 episodes')), findsOneWidget);
    });

    testWidgets('a partial watch leaves a dropped series dropped', (
      tester,
    ) async {
      final repository = _FakeRepo([
        _series(status: MediaStatus.dropped),
      ], episodes: _episodes('series-1'));
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
      );

      await tester.tap(find.byKey(MediaDetailScreen.episodeCheckboxKey(1, 1)));
      await tester.pumpAndSettle();

      expect(repository.writes.last['progress_percent'], 25);
      expect(repository.writes.last.containsKey('status'), isFalse);
      expect(inDetail(find.text('Dropped')), findsWidgets);
    });

    testWidgets(
      'the progress bar reaches 100 % when all episodes are watched',
      (tester) async {
        final repository = _FakeRepo([
          _series(),
        ], episodes: _episodes('series-1'));
        await _openDetail(
          tester,
          items: repository.items,
          title: 'Lost',
          repository: repository,
        );

        for (var episode = 1; episode <= 4; episode++) {
          await tester.tap(
            find.byKey(MediaDetailScreen.episodeCheckboxKey(1, episode)),
          );
          await tester.pumpAndSettle();
        }

        expect(repository.writes.last['progress_percent'], 100);
        expect(repository.writes.last['status'], 'completed');
        expect(inDetail(find.text('Completed')), findsWidgets);
      },
    );

    testWidgets('marking a season watched checks every episode', (
      tester,
    ) async {
      final repository = _FakeRepo([
        _series(),
      ], episodes: _episodes('series-1'));
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
      );

      await tester.ensureVisible(
        find.byKey(MediaDetailScreen.markSeasonWatchedKey),
      );
      await tester.tap(find.byKey(MediaDetailScreen.markSeasonWatchedKey));
      await tester.pumpAndSettle();

      expect(repository.writes.last['progress_percent'], 100);
      expect(repository.writes.last['status'], 'completed');
      expect(inDetail(find.text('Season marked as watched')), findsOneWidget);
    });

    testWidgets('resetting a season asks for confirmation', (tester) async {
      final repository = _FakeRepo([
        _series(status: MediaStatus.completed, percent: 100),
      ], episodes: _episodes('series-1', watched: 4));
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
      );

      await tester.ensureVisible(find.byKey(MediaDetailScreen.resetSeasonKey));
      await tester.tap(find.byKey(MediaDetailScreen.resetSeasonKey));
      await tester.pumpAndSettle();
      expect(find.text('Reset this season?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Reset season'));
      await tester.pumpAndSettle();

      expect(repository.writes.last['progress_percent'], 0);
      expect(inDetail(find.text('0%')), findsWidgets);
      expect(inDetail(find.text('Season reset')), findsOneWidget);
    });

    testWidgets('a TMDB failure shows a retry that can succeed', (
      tester,
    ) async {
      final repository = _FakeRepo([_series(externalId: '95396')]);
      final tmdb = _SeriesTmdb(failTv: true);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
        tmdb: tmdb,
      );

      expect(
        inDetail(find.text('Could not load the episodes')),
        findsOneWidget,
      );
      expect(find.byKey(MediaDetailScreen.retryEpisodesKey), findsOneWidget);

      // Backend recovers → retry loads the episodes.
      tmdb.failTv = false;
      await tester.tap(find.byKey(MediaDetailScreen.retryEpisodesKey));
      await tester.pumpAndSettle();

      expect(inDetail(find.text('Season 1')), findsOneWidget);
      expect(repository.episodes, hasLength(4));
    });

    testWidgets('a failing season is skipped, the others still load', (
      tester,
    ) async {
      final repository = _FakeRepo([_series(externalId: '95396')]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
        tmdb: _SeriesTmdb(
          episodesBySeason: const <int, int>{1: 4, 2: 3},
          failSeasons: const <int>{2},
        ),
      );

      // Season 1 loaded, season 2 failed without aborting the run.
      expect(repository.episodes, hasLength(4));
      expect(inDetail(find.text('Season 1')), findsOneWidget);
      expect(inDetail(find.text('Season 2')), findsNothing);
    });

    testWidgets('a series without episodes shows the empty state', (
      tester,
    ) async {
      final repository = _FakeRepo([_series(externalId: '95396')]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
        tmdb: _SeriesTmdb(episodesBySeason: const <int, int>{}),
      );

      expect(inDetail(find.text('No episodes found')), findsOneWidget);
    });

    testWidgets('German series UI is localized', (tester) async {
      final repository = _FakeRepo([
        _series(),
      ], episodes: _episodes('series-1'));
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        language: AppLanguage.de,
        repository: repository,
      );

      expect(inDetail(find.text('Folgen')), findsWidgets);
      expect(inDetail(find.text('Staffel 1')), findsOneWidget);
      expect(
        inDetail(find.text('Staffel als gesehen markieren')),
        findsOneWidget,
      );
      expect(inDetail(find.text('0 von 4 Folgen')), findsOneWidget);

      // The localized description fallback appears when a row is expanded.
      await tester.tap(find.byKey(MediaDetailScreen.episodeTileKey(1, 1)));
      await tester.pumpAndSettle();
      expect(
        inDetail(find.text('Keine Beschreibung vorhanden.')),
        findsOneWidget,
      );
    });

    testWidgets('tapping a row expands and collapses the description', (
      tester,
    ) async {
      const synopsis = 'Jack wakes up on the beach with no memory.';
      final repository = _FakeRepo([
        _series(),
      ], episodes: _episodes('series-1', overview: synopsis));
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
      );

      // Hidden initially …
      expect(inDetail(find.text(synopsis)), findsNothing);

      // … visible after the first tap on the row …
      await tester.tap(find.byKey(MediaDetailScreen.episodeTileKey(1, 1)));
      await tester.pumpAndSettle();
      expect(inDetail(find.text(synopsis)), findsOneWidget);
      expect(
        find.byKey(MediaDetailScreen.episodeDescriptionKey(1, 1)),
        findsOneWidget,
      );

      // … and hidden again after the second tap.
      await tester.tap(find.byKey(MediaDetailScreen.episodeTileKey(1, 1)));
      await tester.pumpAndSettle();
      expect(inDetail(find.text(synopsis)), findsNothing);
      expect(
        find.byKey(MediaDetailScreen.episodeDescriptionKey(1, 1)),
        findsNothing,
      );
    });

    testWidgets('the checkbox toggles watched independently of expanding', (
      tester,
    ) async {
      const synopsis = 'The survivors explore the wreckage of the plane.';
      final repository = _FakeRepo([
        _series(),
      ], episodes: _episodes('series-1', overview: synopsis));
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
      );
      final writesBefore = repository.writes.length;

      // Expanding the row does not touch the watched state (no write).
      await tester.tap(find.byKey(MediaDetailScreen.episodeTileKey(1, 1)));
      await tester.pumpAndSettle();
      expect(inDetail(find.text(synopsis)), findsOneWidget);
      expect(repository.writes.length, writesBefore);
      expect(inDetail(find.text('0 of 4 episodes')), findsOneWidget);

      // The checkbox still toggles watched while the description is open.
      await tester.tap(find.byKey(MediaDetailScreen.episodeCheckboxKey(1, 1)));
      await tester.pumpAndSettle();
      expect(repository.writes.last['progress_percent'], 25);
      expect(inDetail(find.text('1 of 4 episodes')), findsOneWidget);
      // The expanded description stays open across the checkbox toggle.
      expect(inDetail(find.text(synopsis)), findsOneWidget);
    });

    testWidgets('an episode without a description shows the fallback', (
      tester,
    ) async {
      final repository = _FakeRepo(
        [_series()],
        // No overview → the localized fallback must be shown instead.
        episodes: _episodes('series-1'),
      );
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
      );

      expect(inDetail(find.text('No description available.')), findsNothing);
      await tester.tap(find.byKey(MediaDetailScreen.episodeTileKey(1, 1)));
      await tester.pumpAndSettle();
      expect(inDetail(find.text('No description available.')), findsOneWidget);
    });
  });

  group('delete', () {
    testWidgets('asks for confirmation and removes the entry', (tester) async {
      final repository = _FakeRepo([_movie()]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Inception',
        repository: repository,
      );

      await tester.tap(find.byKey(MediaDetailScreen.deleteButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('Delete this item?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.deleted, ['movie-1']);
      // Popped back to the library, which no longer shows the entry.
      expect(find.byType(MediaDetailScreen), findsNothing);
      expect(find.text('Inception'), findsNothing);
    });

    testWidgets('cancelling keeps the entry', (tester) async {
      final repository = _FakeRepo([_movie()]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Inception',
        repository: repository,
      );

      await tester.tap(find.byKey(MediaDetailScreen.deleteButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deleted, isEmpty);
      expect(find.byType(MediaDetailScreen), findsOneWidget);
    });
  });

  group('missing fields', () {
    testWidgets('a bare book renders without crashing', (tester) async {
      const bare = MediaItem(
        id: 'bare',
        kind: MediaKind.book,
        title: 'Bare Book',
        // no cover, no description, no pages, no authors, no dates
      );
      await _openDetail(tester, items: [bare], title: 'Bare Book');

      expect(inDetail(find.text('No description available.')), findsOneWidget);
      expect(inDetail(find.text('Not set yet')), findsNWidgets(2));
      // No page count → percent slider.
      expect(find.byKey(MediaDetailScreen.percentSliderKey), findsOneWidget);
      expect(find.byKey(MediaDetailScreen.totalPagesFieldKey), findsOneWidget);
    });

    testWidgets('German detail is localized', (tester) async {
      await _openDetail(
        tester,
        items: [_book(totalPages: 300)],
        title: 'Dune',
        language: AppLanguage.de,
      );

      expect(inDetail(find.text('Verfolgung')), findsOneWidget);
      expect(inDetail(find.text('Seiten gesamt')), findsOneWidget);
      expect(inDetail(find.text('Begonnen am')), findsOneWidget);
      expect(inDetail(find.text('Abgeschlossen am')), findsOneWidget);
    });
  });
}

/// Opens the library (the app start tab) without entering a detail — used by
/// the list-level assertions.
Future<void> _pumpLibrary(
  WidgetTester tester, {
  required List<MediaItem> items,
}) async {
  tester.view.physicalSize = const Size(1100, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaTrackerApp(
      themeProvider: ThemeProvider(),
      settingsProvider: SettingsProvider(initial: AppLanguage.en),
      authProvider: _FakeAuth(),
      repository: _FakeRepo(items),
      tmdbClient: _StubTmdb(),
    ),
  );
  await tester.pumpAndSettle();
}
