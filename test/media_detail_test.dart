import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/main.dart';
import 'package:media_tracker/models/media_item.dart';
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

/// Repository stub: an in-memory library that applies tracking writes like
/// PostgREST would and records them.
class _FakeRepo extends MediaRepository {
  _FakeRepo(this.items);

  List<MediaItem> items;

  final List<Map<String, dynamic>> writes = [];
  final List<String> deleted = [];

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
  Future<void> delete(String id) async {
    deleted.add(id);
    items.removeWhere((item) => item.id == id);
  }
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

MediaItem _series({String id = 'series-1', String title = 'Lost'}) => MediaItem(
  id: id,
  kind: MediaKind.series,
  title: title,
  releaseYear: 2004,
  overview: 'Stranded on an island.',
  totalSeasons: 6,
  totalEpisodes: 121,
);

/// Opens the app on a tall surface so the whole detail view fits without
/// scrolling, then taps the entry with [title].
Future<void> _openDetail(
  WidgetTester tester, {
  required List<MediaItem> items,
  required String title,
  AppLanguage language = AppLanguage.en,
  MediaRepository? repository,
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
      tmdbClient: _StubTmdb(),
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
    testWidgets('shows a status badge and progress for movies and books', (
      tester,
    ) async {
      await _pumpLibrary(
        tester,
        items: [
          _movie(percent: 40),
          _book(totalPages: 300, percent: 50, current: 150),
          _series(),
        ],
      );

      // Two progress bars (movie + book), none for the series.
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
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
    testWidgets('shows a notice instead of progress controls', (tester) async {
      final repository = _FakeRepo([_series()]);
      await _openDetail(
        tester,
        items: repository.items,
        title: 'Lost',
        repository: repository,
      );

      expect(
        inDetail(find.text('Episode tracking coming soon')),
        findsOneWidget,
      );
      expect(find.byKey(MediaDetailScreen.percentSliderKey), findsNothing);
      expect(find.byKey(MediaDetailScreen.pageSliderKey), findsNothing);
      expect(find.byKey(MediaDetailScreen.pageFieldKey), findsNothing);
      // The screen stays usable: metadata and delete are present.
      expect(inDetail(find.text('Series')), findsWidgets);
      expect(find.byKey(MediaDetailScreen.deleteButtonKey), findsOneWidget);
    });

    testWidgets('German series notice is localized', (tester) async {
      await _openDetail(
        tester,
        items: [_series()],
        title: 'Lost',
        language: AppLanguage.de,
      );

      expect(inDetail(find.text('Folgen-Verfolgung folgt')), findsOneWidget);
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
