import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/main.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/models/tmdb_result.dart';
import 'package:media_tracker/providers/auth_provider.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/providers/theme_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/services/tmdb_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Repository stub: an empty library and configurable duplicate handling.
class _FakeRepository extends MediaRepository {
  _FakeRepository({this.existing});

  /// Returned by [findByExternal] — non-null simulates "already tracked".
  MediaItem? existing;

  int insertCount = 0;

  /// When set, [insert] throws a [MediaRepositoryException] with this text.
  String? insertError;

  @override
  Future<List<MediaItem>> fetchAll() async => const <MediaItem>[];

  @override
  Future<MediaItem?> findByExternal(String source, String id) async => existing;

  @override
  Future<MediaItem> insert(MediaItem item) async {
    insertCount++;
    final error = insertError;
    if (error != null) throw MediaRepositoryException(error);
    return item.copyWith(id: 'new-id');
  }
}

/// Metadata client stub — no network.
class _FakeTmdb extends TmdbClient {
  _FakeTmdb({
    this.enabled = true,
    this.results = const <TmdbSearchResult>[],
    this.searchError,
  }) : super(
         httpClient: MockClient((_) async => http.Response('{}', 200)),
         token: 'fake',
       );

  final bool enabled;
  final List<TmdbSearchResult> results;
  final String? searchError;

  final List<String> queries = [];

  /// The `language` argument of every [search] call.
  final List<String?> languages = [];

  @override
  bool get hasToken => enabled;

  @override
  Future<List<TmdbSearchResult>> search(
    String query, {
    TmdbSearchScope scope = TmdbSearchScope.all,
    int page = 1,
    String? language,
  }) async {
    queries.add(query);
    languages.add(language);
    final error = searchError;
    if (error != null) throw TmdbException(error);
    return results;
  }

  @override
  Future<TmdbDetails> fetchDetails(
    TmdbSearchResult result, {
    String? language,
  }) async {
    return TmdbMovieDetails(
      id: result.id,
      title: result.title,
      originalTitle: result.originalTitle,
      year: result.year,
      runtime: 148,
      overview: result.overview,
    );
  }
}

const TmdbSearchResult _hit = TmdbSearchResult(
  id: 27205,
  type: TmdbMediaType.movie,
  title: 'Inception',
  originalTitle: 'Inception',
  year: 2010,
  overview: 'A thief who steals corporate secrets.',
);

Future<void> _pumpSearch(
  WidgetTester tester, {
  required TmdbClient tmdb,
  MediaRepository? repository,
  SettingsProvider? settings,
}) async {
  await tester.pumpWidget(
    MediaTrackerApp(
      themeProvider: ThemeProvider(),
      // English by default so the assertions below stay readable; the app
      // default is German (covered by dedicated tests).
      settingsProvider: settings ?? SettingsProvider(initial: AppLanguage.en),
      authProvider: _FakeAuth(),
      repository: repository ?? _FakeRepository(),
      tmdbClient: tmdb,
    ),
  );
  await tester.pump();
  // Switch to the Search tab via its nav icon — language-agnostic so the
  // German tests work too.
  await tester.tap(find.byIcon(Icons.search));
  await tester.pumpAndSettle();
}

void main() {
  // Language switches persist via SharedPreferences — give it a mock store.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('idle state explains what can be searched', (tester) async {
    await _pumpSearch(tester, tmdb: _FakeTmdb());

    expect(find.text('Find something to track'), findsOneWidget);
    expect(find.text('Search for movies and series by title.'), findsOneWidget);
  });

  testWidgets('results appear after the debounce', (tester) async {
    final tmdb = _FakeTmdb(results: const [_hit]);
    await _pumpSearch(tester, tmdb: tmdb);

    await tester.enterText(find.byType(TextField), 'incep');
    // Not yet — the 400ms debounce has not elapsed.
    expect(tmdb.queries, isEmpty);

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(tmdb.queries, ['incep']);
    // English active → TMDB is queried in English.
    expect(tmdb.languages, ['en-US']);
    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('Movie'), findsOneWidget);
  });

  testWidgets('a single character does not trigger a search', (tester) async {
    final tmdb = _FakeTmdb(results: const [_hit]);
    await _pumpSearch(tester, tmdb: tmdb);

    await tester.enterText(find.byType(TextField), 'i');
    await tester.pump(const Duration(milliseconds: 600));

    expect(tmdb.queries, isEmpty);
    expect(find.text('Find something to track'), findsOneWidget);
  });

  testWidgets('shows an empty state when nothing matches', (tester) async {
    await _pumpSearch(tester, tmdb: _FakeTmdb());

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('surfaces a search error with a retry', (tester) async {
    final tmdb = _FakeTmdb(searchError: 'Too many requests to TMDB.');
    await _pumpSearch(tester, tmdb: tmdb);

    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(find.text('Search failed'), findsOneWidget);
    expect(find.text('Too many requests to TMDB.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('explains a missing token instead of crashing', (tester) async {
    await _pumpSearch(tester, tmdb: _FakeTmdb(enabled: false));

    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(find.text('Search failed'), findsOneWidget);
    expect(find.textContaining('TMDB token'), findsOneWidget);
  });

  testWidgets('detail sheet adds an item to the library', (tester) async {
    final repository = _FakeRepository();
    final tmdb = _FakeTmdb(results: const [_hit]);
    await _pumpSearch(tester, tmdb: tmdb, repository: repository);

    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inception'));
    await tester.pumpAndSettle();

    expect(find.text('Add to library'), findsOneWidget);
    expect(find.text('148 min'), findsOneWidget);

    await tester.tap(find.text('Add to library'));
    await tester.pumpAndSettle();

    expect(repository.insertCount, 1);
    expect(find.text('Already in your library'), findsOneWidget);
    expect(find.text('Add to library'), findsNothing);
  });

  testWidgets('detail sheet shows a duplicate as already tracked', (
    tester,
  ) async {
    final repository = _FakeRepository(
      existing: const MediaItem(
        id: 'existing',
        kind: MediaKind.movie,
        title: 'Inception',
        externalSource: 'tmdb',
        externalId: '27205',
      ),
    );
    await _pumpSearch(
      tester,
      tmdb: _FakeTmdb(results: const [_hit]),
      repository: repository,
    );

    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inception'));
    await tester.pumpAndSettle();

    expect(find.text('Already in your library'), findsOneWidget);
    expect(find.text('Add to library'), findsNothing);
  });

  testWidgets('German UI queries TMDB with de-DE', (tester) async {
    final tmdb = _FakeTmdb(results: const [_hit]);
    await _pumpSearch(tester, tmdb: tmdb, settings: SettingsProvider());

    expect(find.text('Finde etwas zum Verfolgen'), findsOneWidget);
    expect(find.text('Filme und Serien suchen'), findsOneWidget);
    expect(find.text('Alle'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'incep');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(tmdb.queries, ['incep']);
    // German active → TMDB is queried in German.
    expect(tmdb.languages, ['de-DE']);
    expect(find.text('Film'), findsOneWidget);
  });

  testWidgets('German empty state is localized', (tester) async {
    await _pumpSearch(tester, tmdb: _FakeTmdb(), settings: SettingsProvider());

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(find.text('Keine Treffer'), findsOneWidget);
  });

  testWidgets('German detail sheet is localized', (tester) async {
    final tmdb = _FakeTmdb(results: const [_hit]);
    await _pumpSearch(tester, tmdb: tmdb, settings: SettingsProvider());

    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inception'));
    await tester.pumpAndSettle();

    expect(find.text('Zur Bibliothek hinzufügen'), findsOneWidget);
    expect(find.text('148 Min.'), findsOneWidget);
  });

  testWidgets('switching language re-queries TMDB with the new code',
      (tester) async {
    final tmdb = _FakeTmdb(results: const [_hit]);
    final settings = SettingsProvider(initial: AppLanguage.en);
    await _pumpSearch(tester, tmdb: tmdb, settings: settings);

    await tester.enterText(find.byType(TextField), 'inception');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(tmdb.languages, ['en-US']);

    // Switch to German and search again — the next request must use de-DE
    // without recreating the widget tree.
    await settings.setLanguage(AppLanguage.de);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'herr der ringe');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(tmdb.languages, ['en-US', 'de-DE']);
  });
}
