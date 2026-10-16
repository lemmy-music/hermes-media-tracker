import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/main.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/providers/auth_provider.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/providers/theme_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/screens/library_screen.dart';
import 'package:media_tracker/widgets/category_banner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// fakes — no Supabase, no network
// ─────────────────────────────────────────────────────────────────────────────

class _FakeAuth extends AuthProvider {
  @override
  AuthStatus get status => AuthStatus.signedIn;

  @override
  String? get email => 'me@example.com';

  @override
  Future<String?> sendMagicLink(String email) async => null;

  @override
  Future<String?> verifyEmailCode({
    required String email,
    required String code,
  }) async => null;

  @override
  Future<void> signOut() async {}
}

/// In-memory repository; [fetchAll] never touches the network.
class _FakeRepository extends MediaRepository {
  _FakeRepository({this.items = const <MediaItem>[], this.error});

  List<MediaItem> items;

  /// When set, [fetchAll] throws a [MediaRepositoryException] with this text.
  String? error;

  /// When set, [fetchAll] hangs on this completer instead of resolving.
  Completer<List<MediaItem>>? pending;

  int fetchCount = 0;

  @override
  Future<List<MediaItem>> fetchAll() async {
    fetchCount++;
    final pending = this.pending;
    if (pending != null) return pending.future;
    final error = this.error;
    if (error != null) throw MediaRepositoryException(error);
    return items;
  }
}

MediaItem _movie(String title, {String? posterUrl, DateTime? createdAt}) =>
    MediaItem(
      id: 'movie-$title',
      kind: MediaKind.movie,
      title: title,
      posterUrl: posterUrl,
      createdAt: createdAt,
    );

MediaItem _series(String title, {String? posterUrl, DateTime? createdAt}) =>
    MediaItem(
      id: 'series-$title',
      kind: MediaKind.series,
      title: title,
      posterUrl: posterUrl,
      createdAt: createdAt,
    );

MediaItem _book(String title, {String? posterUrl, DateTime? createdAt}) =>
    MediaItem(
      id: 'book-$title',
      kind: MediaKind.book,
      title: title,
      posterUrl: posterUrl,
      createdAt: createdAt,
    );

/// Finds an [Image] backed by a [NetworkImage] for [url] — the banner renders
/// the same cover in several layers, so this matches one or more.
Finder _imageWithUrl(String url) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is NetworkImage &&
      (widget.image as NetworkImage).url == url,
);

Future<void> _pump(
  WidgetTester tester, {
  required MediaRepository repository,
  AppLanguage language = AppLanguage.en,
}) async {
  await tester.pumpWidget(
    MediaTrackerApp(
      themeProvider: ThemeProvider(),
      settingsProvider: SettingsProvider(initial: language),
      authProvider: _FakeAuth(),
      repository: repository,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('renders four category banners with the loaded counts', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        items: [
          _movie('Inception'),
          _movie('Arrival'),
          _series('Dark'),
          _book('Dune'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CategoryBanner), findsNWidgets(4));
    expect(find.byKey(LibraryScreen.movieTileKey), findsOneWidget);
    expect(find.byKey(LibraryScreen.seriesTileKey), findsOneWidget);
    expect(find.byKey(LibraryScreen.bookTileKey), findsOneWidget);
    expect(find.byKey(LibraryScreen.allTileKey), findsOneWidget);

    // Tile headings (plural) and singular/plural-aware counts.
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('2 movies'), findsOneWidget);
    expect(find.text('1 series'), findsOneWidget);
    expect(find.text('1 book'), findsOneWidget);
    expect(find.text('4 items'), findsOneWidget);
  });

  testWidgets('shows a zero count for a category without items', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        items: [_movie('Inception'), _movie('Arrival')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 movies'), findsOneWidget);
    expect(find.text('0 series'), findsOneWidget);
    expect(find.text('0 books'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('uses the singular count for exactly one item', (tester) async {
    await _pump(
      tester,
      repository: _FakeRepository(items: [_movie('Inception')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 movie'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
  });

  testWidgets('shows a loading indicator while the library loads', (
    tester,
  ) async {
    final repository = _FakeRepository()
      ..pending = Completer<List<MediaItem>>();
    await _pump(tester, repository: repository);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(LibraryScreen.allTileKey), findsNothing);

    // Resolve so no timers / futures leak into the next test.
    repository.pending!.complete(<MediaItem>[]);
    await tester.pumpAndSettle();
  });

  testWidgets('shows the error state with a working retry', (tester) async {
    final repository = _FakeRepository(error: 'Could not load your library.');
    await _pump(tester, repository: repository);
    await tester.pumpAndSettle();

    expect(find.text('Could not load your library'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byKey(LibraryScreen.allTileKey), findsNothing);

    // Backend recovers → retry loads the tiles.
    repository
      ..error = null
      ..items = [_movie('Inception')];

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repository.fetchCount, 2);
    expect(find.byKey(LibraryScreen.allTileKey), findsOneWidget);
    expect(find.text('1 movie'), findsOneWidget);
  });

  testWidgets('an empty library keeps the friendly empty state', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeRepository());
    await tester.pumpAndSettle();

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.byKey(LibraryScreen.allTileKey), findsNothing);
    expect(find.byKey(LibraryScreen.movieTileKey), findsNothing);
  });

  testWidgets('tapping Movies opens the list filtered to movies only', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        items: [_movie('Inception'), _series('Dark'), _book('Dune')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LibraryScreen.movieTileKey));
    await tester.pumpAndSettle();

    // Pushed page with the matching title and a back arrow.
    expect(find.widgetWithText(AppBar, 'Movies'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    // Only movies are listed…
    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('Dark'), findsNothing);
    expect(find.text('Dune'), findsNothing);

    // …and the media-type chip shows the preselected kind (not "All").
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Movies'),
    );
    expect(chip.selected, isTrue);
    expect(find.text('1 result of 3'), findsOneWidget);

    // Back navigation returns to the tiles.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(LibraryScreen.allTileKey), findsOneWidget);
  });

  testWidgets('tapping All opens the list with no filter', (tester) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        items: [_movie('Inception'), _series('Dark'), _book('Dune')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LibraryScreen.allTileKey));
    await tester.pumpAndSettle();

    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    // No filter active → no result counter.
    expect(find.textContaining('result of'), findsNothing);
  });

  testWidgets('a preselected category can still be changed in the list', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(items: [_movie('Inception'), _book('Dune')]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LibraryScreen.bookTileKey));
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Inception'), findsNothing);

    // The user changes the filter freely — here back to movies.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Movies'));
    await tester.pumpAndSettle();

    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('the tiles are localized in German', (tester) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        items: [_movie('Inception'), _series('Dark'), _book('Dune')],
      ),
      language: AppLanguage.de,
    );
    await tester.pumpAndSettle();

    expect(find.text('Nach Kategorie stöbern'), findsOneWidget);
    expect(find.text('Filme'), findsOneWidget);
    expect(find.text('Serien'), findsOneWidget);
    expect(find.text('Bücher'), findsOneWidget);
    expect(find.text('Alle'), findsOneWidget);
    expect(find.text('1 Film'), findsOneWidget);
    expect(find.text('1 Serie'), findsOneWidget);
    expect(find.text('1 Buch'), findsOneWidget);
    expect(find.text('3 Einträge'), findsOneWidget);
  });

  // ── banner artwork ─────────────────────────────────────────────────────────

  testWidgets('a banner with a cover renders that cover as artwork', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        items: [
          _movie(
            'Inception',
            posterUrl: 'https://image.tmdb.org/t/p/w342/incep.jpg',
            createdAt: DateTime(2026),
          ),
          _movie(
            'Arrival',
            posterUrl: 'https://image.tmdb.org/t/p/w342/arrival.jpg',
            createdAt: DateTime(2024),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // The newest cover is the hero (background + deck front)…
    expect(
      _imageWithUrl('https://image.tmdb.org/t/p/w342/incep.jpg'),
      findsWidgets,
    );
    // …the older one fans behind it.
    expect(
      _imageWithUrl('https://image.tmdb.org/t/p/w342/arrival.jpg'),
      findsWidgets,
    );
  });

  testWidgets('a category without a cover shows the gradient fallback', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        items: [
          _movie(
            'Inception',
            posterUrl: 'https://image.tmdb.org/t/p/w342/incep.jpg',
            createdAt: DateTime(2026),
          ),
          // Typical OpenLibrary book: no cover at all.
          _book('Dune', createdAt: DateTime(2025)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // The book banner exists, is intact, and renders no image at all…
    final bookBanner = find.byKey(LibraryScreen.bookTileKey);
    expect(bookBanner, findsOneWidget);
    expect(
      find.descendant(of: bookBanner, matching: find.byType(Image)),
      findsNothing,
    );
    // …but still shows its icon + label + count (a deliberate fallback).
    expect(
      find.descendant(of: bookBanner, matching: find.byType(Icon)),
      findsWidgets,
    );
    expect(find.text('1 book'), findsOneWidget);

    // The movie banner, in contrast, does render its cover.
    expect(
      _imageWithUrl('https://image.tmdb.org/t/p/w342/incep.jpg'),
      findsWidgets,
    );
  });

  testWidgets('a broken cover URL degrades to the fallback without crashing', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        items: [
          _movie(
            'Inception',
            posterUrl: 'https://image.invalid/nope.jpg',
            createdAt: DateTime(2026),
          ),
        ],
      ),
    );
    // The test HTTP stack answers every request with an error; the shared
    // CoverImage placeholder must swallow it (no exception, no crash).
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(LibraryScreen.movieTileKey), findsOneWidget);
    expect(find.text('1 movie'), findsOneWidget);
  });

  testWidgets('tapping a banner opens the list filtered to its category', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        items: [
          _movie(
            'Inception',
            posterUrl: 'https://image.tmdb.org/t/p/w342/incep.jpg',
            createdAt: DateTime(2026),
          ),
          _book('Dune', createdAt: DateTime(2025)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LibraryScreen.bookTileKey));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Books'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Inception'), findsNothing);
  });
}
