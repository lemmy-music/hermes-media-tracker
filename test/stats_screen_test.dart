import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/models/episode.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/screens/stats_screen.dart';

/// In-memory repository — no Supabase, no network.
class _FakeRepository extends MediaRepository {
  _FakeRepository({
    this.items = const <MediaItem>[],
    this.episodes = const <Episode>[],
    this.error,
  });

  List<MediaItem> items;
  List<Episode> episodes;

  /// When set, both fetches throw a [MediaRepositoryException] with this text.
  String? error;

  int fetchAllCount = 0;
  int fetchEpisodesCount = 0;

  @override
  Future<List<MediaItem>> fetchAll() async {
    fetchAllCount++;
    final error = this.error;
    if (error != null) throw MediaRepositoryException(error);
    return items;
  }

  @override
  Future<List<Episode>> fetchAllEpisodes() async {
    fetchEpisodesCount++;
    final error = this.error;
    if (error != null) throw MediaRepositoryException(error);
    return episodes;
  }
}

final DateTime _now = DateTime(2026, 6, 15, 12);

MediaItem _movie({
  String id = 'm1',
  DateTime? completedAt,
  int? runtime,
  MediaStatus status = MediaStatus.completed,
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
  DateTime? completedAt,
  int? totalPages,
  MediaStatus status = MediaStatus.completed,
}) => MediaItem(
  id: id,
  kind: MediaKind.book,
  title: 'Book $id',
  status: status,
  completedAt: completedAt,
  totalPages: totalPages,
);

MediaItem _series({String id = 's1'}) =>
    MediaItem(id: id, kind: MediaKind.series, title: 'Series $id');

Episode _episode({String id = 'e1', DateTime? watchedAt, int? runtime}) =>
    Episode(
      id: id,
      mediaItemId: 's1',
      seasonNumber: 1,
      episodeNumber: 1,
      watched: true,
      watchedAt: watchedAt,
      runtime: runtime,
    );

Future<void> _pumpStats(
  WidgetTester tester, {
  required MediaRepository repository,
  AppLanguage language = AppLanguage.en,
}) async {
  // A tall, roomy surface so every block (and the range switcher) is on
  // screen without scrolling.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(
          value: SettingsProvider(initial: language),
        ),
        Provider<MediaRepository>.value(value: repository),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: StatsScreen(clock: () => _now),
      ),
    ),
  );
  // The load is kicked off in a post-frame callback.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('renders both blocks with the aggregated numbers', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRepository(
      items: [
        _movie(id: 'a', completedAt: DateTime(2026, 6, 2), runtime: 90),
        _book(id: 'b', completedAt: DateTime(2026, 6, 3), totalPages: 300),
        _series(id: 'c'),
      ],
      episodes: [
        _episode(id: 'e1', watchedAt: DateTime(2026, 6, 4), runtime: 40),
      ],
    );
    await _pumpStats(tester, repository: repository);

    // Block 1.
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Status distribution'), findsOneWidget);
    expect(find.text('Completion rate'), findsOneWidget);
    expect(find.text('Movies'), findsWidgets);
    expect(find.text('Books'), findsWidgets);

    // Block 2 — default range is 12 months.
    expect(find.text('Completions over time'), findsOneWidget);
    expect(find.text('TV minutes'), findsOneWidget);
    expect(find.text('Pages'), findsOneWidget);
    // 90 (movie) + 40 (episode) = 130 min → "2 h 10 min".
    expect(find.text('2 h 10 min'), findsOneWidget);
    expect(find.text('300 pages'), findsOneWidget);

    expect(repository.fetchAllCount, 1);
    expect(repository.fetchEpisodesCount, 1);
  });

  testWidgets('shows a friendly empty state for an empty library', (
    WidgetTester tester,
  ) async {
    await _pumpStats(tester, repository: _FakeRepository());

    expect(find.text('No stats yet'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
    expect(find.text('Completions over time'), findsNothing);
  });

  testWidgets('the range switcher changes the numbers', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRepository(
      items: [
        // February completion: only inside the 6/12-month windows.
        _movie(id: 'feb', completedAt: DateTime(2026, 2, 10), runtime: 30),
        // June completion: inside every window.
        _movie(id: 'jun', completedAt: DateTime(2026, 6, 10), runtime: 90),
      ],
    );
    await _pumpStats(tester, repository: repository);

    // All four range chips are offered.
    expect(find.text('1 month'), findsOneWidget);
    expect(find.text('6 months'), findsOneWidget);
    expect(find.text('12 months'), findsOneWidget);
    expect(find.text('All time'), findsOneWidget);

    // Default (12 months): 30 + 90 = 120 min → "2 h".
    expect(find.text('2 h'), findsOneWidget);

    // Switch to 1 month → only the June completion (90 min → "1 h 30 min").
    await tester.tap(find.text('1 month'));
    await tester.pumpAndSettle();
    expect(find.text('1 h 30 min'), findsOneWidget);
    expect(find.text('2 h'), findsNothing);

    // Switching back to all time brings February back.
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('2 h'), findsOneWidget);
  });

  testWidgets('surfaces a load error with a working retry', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRepository(error: 'Backend unavailable.');
    await _pumpStats(tester, repository: repository);

    expect(find.text('Could not load your stats'), findsOneWidget);
    expect(find.text('Backend unavailable.'), findsOneWidget);

    repository
      ..error = null
      ..items = [_movie(id: 'a', completedAt: DateTime(2026, 6, 2))];

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Overview'), findsOneWidget);
    expect(repository.fetchAllCount, 2);
  });

  testWidgets('the refresh button reloads the data', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRepository(
      items: [_movie(id: 'a', completedAt: DateTime(2026, 6, 2))],
    );
    await _pumpStats(tester, repository: repository);
    expect(repository.fetchAllCount, 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump();

    expect(repository.fetchAllCount, 2);
    expect(repository.fetchEpisodesCount, 2);
  });

  testWidgets('renders localized German copy', (WidgetTester tester) async {
    final repository = _FakeRepository(
      items: [_movie(id: 'a', completedAt: DateTime(2026, 6, 2), runtime: 90)],
    );
    await _pumpStats(tester, repository: repository, language: AppLanguage.de);

    expect(find.text('Überblick'), findsOneWidget);
    expect(find.text('Status-Verteilung'), findsOneWidget);
    expect(find.text('Abschlussquote'), findsOneWidget);
    expect(find.text('Abschlüsse über Zeit'), findsOneWidget);
    expect(find.text('TV-Minuten'), findsOneWidget);
    expect(find.text('Gesamt'), findsOneWidget);
    expect(find.text('1 Std. 30 Min.'), findsOneWidget);
  });
}
