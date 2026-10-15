import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/main.dart';
import 'package:media_tracker/models/book_result.dart';
import 'package:media_tracker/models/episode.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/models/reading_log_entry.dart';
import 'package:media_tracker/models/tmdb_result.dart';
import 'package:media_tracker/providers/auth_provider.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/providers/theme_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/services/openlibrary_client.dart';
import 'package:media_tracker/services/tmdb_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// fakes (no network, no Supabase)
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

/// Repository stub whose [fetchAll] serves the configured library list (or
/// fails). Everything else is inert — these tests never open a detail sheet.
class _FakeRepository extends MediaRepository {
  _FakeRepository({
    List<MediaItem> items = const <MediaItem>[],
    this.failLoad = false,
  }) : items = List<MediaItem>.of(items);

  final List<MediaItem> items;

  /// When `true`, [fetchAll] throws to simulate an unloadable library.
  final bool failLoad;

  @override
  Future<List<MediaItem>> fetchAll() async {
    if (failLoad) {
      throw const MediaRepositoryException('Could not load your library.');
    }
    return items;
  }

  @override
  Future<MediaItem?> findByExternal(String source, String id) async => null;

  @override
  Future<MediaItem> insert(MediaItem item) async => item.copyWith(id: 'new-id');

  @override
  Future<MediaItem> updateTracking(
    String id,
    Map<String, dynamic> fields,
  ) async => MediaItem(id: id, kind: MediaKind.movie, title: '');

  @override
  Future<ReadingLogEntry> insertReadingLog({
    required String mediaItemId,
    required int pages,
    DateTime? loggedAt,
  }) async => ReadingLogEntry(
    mediaItemId: mediaItemId,
    pages: pages,
    loggedAt: loggedAt,
  );

  @override
  Future<List<Episode>> fetchEpisodes(String mediaItemId) async =>
      const <Episode>[];
}

/// TMDB stub — returns the configured hits for any query.
class _FakeTmdb extends TmdbClient {
  _FakeTmdb({this.results = const <TmdbSearchResult>[]})
    : super(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        token: 'fake',
      );

  final List<TmdbSearchResult> results;

  @override
  bool get hasToken => true;

  @override
  Future<List<TmdbSearchResult>> search(
    String query, {
    TmdbSearchScope scope = TmdbSearchScope.all,
    int page = 1,
    String? language,
  }) async => results;

  @override
  Future<TmdbDetails> fetchDetails(
    TmdbSearchResult result, {
    String? language,
  }) async => TmdbMovieDetails(
    id: result.id,
    title: result.title,
    originalTitle: result.originalTitle,
    year: result.year,
    runtime: 148,
    overview: result.overview,
  );
}

/// OpenLibrary stub — returns the configured book hits.
class _FakeOpenLibrary extends OpenLibraryClient {
  _FakeOpenLibrary({this.results = const <BookResult>[]})
    : super(httpClient: MockClient((_) async => http.Response('{}', 200)));

  final List<BookResult> results;

  @override
  Future<List<BookResult>> search(
    String query, {
    int limit = OpenLibraryClient.defaultLimit,
    AppLanguage? language,
  }) async => results;

  @override
  Future<BookDetails> fetchDetails(
    String workKey, {
    AppLanguage? language,
  }) async => BookDetails(key: workKey, title: 'book');
}

const TmdbSearchResult _movieHit = TmdbSearchResult(
  id: 27205,
  type: TmdbMediaType.movie,
  title: 'Inception',
  year: 2010,
);

const BookResult _bookHit = BookResult(
  key: '/works/OL27448W',
  title: 'The Lord of the Rings',
  authors: ['J.R.R. Tolkien'],
  firstPublishYear: 1954,
);

MediaItem _libraryItem({
  required String source,
  required String externalId,
  required MediaStatus status,
  MediaKind kind = MediaKind.movie,
}) => MediaItem(
  id: 'lib-1',
  kind: kind,
  title: 'Tracked',
  externalSource: source,
  externalId: externalId,
  status: status,
);

Future<void> _pumpSearch(
  WidgetTester tester, {
  required MediaRepository repository,
  TmdbClient? tmdb,
  OpenLibraryClient? books,
  AppLanguage language = AppLanguage.en,
}) async {
  await tester.pumpWidget(
    MediaTrackerApp(
      themeProvider: ThemeProvider(),
      settingsProvider: SettingsProvider(initial: language),
      authProvider: _FakeAuth(),
      repository: repository,
      tmdbClient: tmdb ?? _FakeTmdb(results: const [_movieHit]),
      openLibraryClient: books ?? _FakeOpenLibrary(),
    ),
  );
  await tester.pump();
  // Switch to the Search tab via its nav icon (language-agnostic).
  await tester.tap(find.byIcon(Icons.search));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('an untracked hit shows no status badges', (tester) async {
    await _pumpSearch(tester, repository: _FakeRepository());
    await _search(tester, 'inception');

    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('In library'), findsNothing);
    expect(find.text('Watched'), findsNothing);
  });

  testWidgets('a planned entry shows only the "In library" badge', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      repository: _FakeRepository(
        items: <MediaItem>[
          _libraryItem(
            source: 'tmdb',
            externalId: '27205',
            status: MediaStatus.planned,
          ),
        ],
      ),
    );
    await _search(tester, 'inception');

    expect(find.text('In library'), findsOneWidget);
    expect(find.text('Watched'), findsNothing);
  });

  testWidgets('an in-progress entry shows only the "In library" badge', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      repository: _FakeRepository(
        items: <MediaItem>[
          _libraryItem(
            source: 'tmdb',
            externalId: '27205',
            status: MediaStatus.inProgress,
          ),
        ],
      ),
    );
    await _search(tester, 'inception');

    expect(find.text('In library'), findsOneWidget);
    expect(find.text('Watched'), findsNothing);
  });

  testWidgets('a completed entry shows BOTH badges', (tester) async {
    await _pumpSearch(
      tester,
      repository: _FakeRepository(
        items: <MediaItem>[
          _libraryItem(
            source: 'tmdb',
            externalId: '27205',
            status: MediaStatus.completed,
          ),
        ],
      ),
    );
    await _search(tester, 'inception');

    // Completed implies "in the library", so both badges appear.
    expect(find.text('In library'), findsOneWidget);
    expect(find.text('Watched'), findsOneWidget);
  });

  testWidgets(
    'a completed book hit resolves through the OpenLibrary work key',
    (tester) async {
      await _pumpSearch(
        tester,
        repository: _FakeRepository(
          items: <MediaItem>[
            _libraryItem(
              source: 'openlibrary',
              externalId: '/works/OL27448W',
              status: MediaStatus.completed,
              kind: MediaKind.book,
            ),
          ],
        ),
        tmdb: _FakeTmdb(),
        books: _FakeOpenLibrary(results: const [_bookHit]),
      );

      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      await _search(tester, 'lotr');

      expect(find.text('The Lord of the Rings'), findsOneWidget);
      expect(find.text('In library'), findsOneWidget);
      expect(find.text('Watched'), findsOneWidget);
    },
  );

  testWidgets('a failed library load keeps the search working without badges', (
    tester,
  ) async {
    await _pumpSearch(tester, repository: _FakeRepository(failLoad: true));
    await _search(tester, 'inception');

    // The search itself is unaffected: the hit is still listed…
    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('Movie'), findsOneWidget);
    // …and no badge claims anything about a library we could not load.
    expect(find.text('In library'), findsNothing);
    expect(find.text('Watched'), findsNothing);
  });

  testWidgets('the badges are localized for German', (tester) async {
    await _pumpSearch(
      tester,
      repository: _FakeRepository(
        items: <MediaItem>[
          _libraryItem(
            source: 'tmdb',
            externalId: '27205',
            status: MediaStatus.completed,
          ),
        ],
      ),
      language: AppLanguage.de,
    );
    await _search(tester, 'inception');

    expect(find.text('In der Bibliothek'), findsOneWidget);
    expect(find.text('Gesehen'), findsOneWidget);
  });
}
