import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
///
/// Also supports the "add as watched" flow: an in-memory episode store plus a
/// tracking/reading-log recorder, so the real [LibraryProvider] write paths can
/// run against it (no Supabase, no network).
class _FakeRepository extends MediaRepository {
  _FakeRepository({this.existing, List<Episode> episodes = const <Episode>[]})
    : episodes = List<Episode>.of(episodes);

  /// Returned by [findByExternal] — non-null simulates "already tracked".
  MediaItem? existing;

  int insertCount = 0;

  /// The item handed to the most recent [insert] call.
  MediaItem? lastInserted;

  /// When set, [insert] throws a [MediaRepositoryException] with this text.
  String? insertError;

  /// In-memory episode store (keyed by `media_item_id`).
  List<Episode> episodes;

  /// Every tracking write (as the fields map that was sent).
  final List<Map<String, dynamic>> trackingWrites = <Map<String, dynamic>>[];

  /// Every reading-log payload that was written.
  final List<Map<String, dynamic>> readingLogs = <Map<String, dynamic>>[];

  @override
  Future<List<MediaItem>> fetchAll() async => const <MediaItem>[];

  @override
  Future<MediaItem?> findByExternal(String source, String id) async => existing;

  @override
  Future<MediaItem> insert(MediaItem item) async {
    insertCount++;
    lastInserted = item;
    final error = insertError;
    if (error != null) throw MediaRepositoryException(error);
    return item.copyWith(id: 'new-id');
  }

  @override
  Future<MediaItem> updateTracking(
    String id,
    Map<String, dynamic> fields,
  ) async {
    trackingWrites.add(fields);
    final base =
        lastInserted ??
        const MediaItem(id: 'new-id', kind: MediaKind.movie, title: '');
    final row = Map<String, dynamic>.from(base.toMap())
      ..['id'] = id
      ..addAll(fields);
    return MediaItem.fromMap(row);
  }

  @override
  Future<ReadingLogEntry> insertReadingLog({
    required String mediaItemId,
    required int pages,
    DateTime? loggedAt,
  }) async {
    readingLogs.add(<String, dynamic>{
      'media_item_id': mediaItemId,
      'pages': pages,
    });
    return ReadingLogEntry(
      mediaItemId: mediaItemId,
      pages: pages,
      loggedAt: loggedAt,
    );
  }

  @override
  Future<List<Episode>> fetchEpisodes(String mediaItemId) async =>
      episodes.where((episode) => episode.mediaItemId == mediaItemId).toList();

  @override
  Future<List<Episode>> markSeasonWatched(
    String mediaItemId,
    int seasonNumber,
  ) async {
    final updated = <Episode>[];
    for (var i = 0; i < episodes.length; i++) {
      final episode = episodes[i];
      if (episode.mediaItemId != mediaItemId ||
          episode.seasonNumber != seasonNumber) {
        continue;
      }
      final next = episode.copyWith(
        watched: true,
        watchedAt: DateTime.utc(2026, 1, 1),
      );
      episodes[i] = next;
      updated.add(next);
    }
    return updated;
  }
}

/// Metadata client stub — no network.
class _FakeTmdb extends TmdbClient {
  _FakeTmdb({
    this.enabled = true,
    this.results = const <TmdbSearchResult>[],
    this.searchError,
    this.tvSeasons = const <int, int>{},
    this.failTv = false,
  }) : super(
         httpClient: MockClient((_) async => http.Response('{}', 200)),
         token: 'fake',
       );

  final bool enabled;
  final List<TmdbSearchResult> results;
  final String? searchError;

  /// Season number → episode count for the TV details stub (`_tvHit`).
  final Map<int, int> tvSeasons;

  /// When `true`, [fetchTv] throws — simulates a failed episode load.
  final bool failTv;

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
    if (result.type == TmdbMediaType.tv) {
      final seasons = tvSeasons.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return TmdbTvDetails(
        id: result.id,
        name: result.title,
        originalName: result.originalTitle,
        year: result.year,
        numberOfSeasons: tvSeasons.isEmpty ? null : tvSeasons.length,
        numberOfEpisodes: tvSeasons.isEmpty
            ? null
            : tvSeasons.values.fold<int>(0, (a, b) => a + b),
        seasons: [
          for (final entry in seasons)
            TmdbSeasonSummary(
              seasonNumber: entry.key,
              name: 'Season ${entry.key}',
              episodeCount: entry.value,
            ),
        ],
        overview: result.overview,
      );
    }
    return TmdbMovieDetails(
      id: result.id,
      title: result.title,
      originalTitle: result.originalTitle,
      year: result.year,
      runtime: 148,
      overview: result.overview,
    );
  }

  /// The lazy episode loader fetches this — [failTv] simulates a failed load.
  @override
  Future<TmdbTvDetails> fetchTv(int id, {String? language}) async {
    if (failTv) throw const TmdbException('TMDB request failed.');
    return super.fetchTv(id, language: language);
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

/// A series hit — drives the "mark as watched" series flow.
const TmdbSearchResult _tvHit = TmdbSearchResult(
  id: 9001,
  type: TmdbMediaType.tv,
  title: 'Lost',
  originalTitle: 'Lost',
  year: 2004,
  overview: 'Stranded on an island.',
);

/// Seeds [count] episodes of season 1 for [mediaItemId].
List<Episode> _episodesFor(String mediaItemId, int count) => <Episode>[
  for (var i = 1; i <= count; i++)
    Episode(
      id: 'ep-1-$i',
      mediaItemId: mediaItemId,
      seasonNumber: 1,
      episodeNumber: i,
      name: 'Episode $i',
      runtime: 42,
    ),
];

/// Book client stub — no network. Records the requested languages so the
/// German ranking parameter can be asserted.
class _FakeOpenLibrary extends OpenLibraryClient {
  _FakeOpenLibrary({
    this.results = const <BookResult>[],
    this.searchError,
    this.details,
    this.isbnResult,
    this.isbnError,
  }) : super(httpClient: MockClient((_) async => http.Response('{}', 200)));

  final List<BookResult> results;
  final String? searchError;
  final BookDetails? details;

  /// Returned by [lookupByIsbn]; `null` simulates "no book for this ISBN".
  final BookResult? isbnResult;

  /// When set, [lookupByIsbn] throws an [OpenLibraryException] with this text.
  final String? isbnError;

  final List<String> queries = [];
  final List<AppLanguage?> languages = [];

  /// The (normalized) ISBNs passed to [lookupByIsbn].
  final List<String> isbnQueries = [];

  /// The `language` argument of every [lookupByIsbn] call.
  final List<AppLanguage?> isbnLanguages = [];

  @override
  Future<List<BookResult>> search(
    String query, {
    int limit = OpenLibraryClient.defaultLimit,
    AppLanguage? language,
  }) async {
    queries.add(query);
    languages.add(language);
    final error = searchError;
    if (error != null) throw OpenLibraryException(error);
    return results;
  }

  @override
  Future<BookResult?> lookupByIsbn(String isbn, {AppLanguage? language}) async {
    isbnQueries.add(isbn);
    isbnLanguages.add(language);
    final error = isbnError;
    if (error != null) throw OpenLibraryException(error);
    return isbnResult;
  }

  @override
  Future<BookDetails> fetchDetails(
    String workKey, {
    AppLanguage? language,
  }) async {
    return details ??
        BookDetails(
          key: workKey,
          title: results.isEmpty ? '' : results.first.title,
        );
  }
}

const BookResult _bookHit = BookResult(
  key: '/works/OL27448W',
  title: 'The Lord of the Rings',
  authors: ['J.R.R. Tolkien'],
  firstPublishYear: 1954,
  coverId: 8231856,
  pageCount: 1216,
  isbns: ['9780618640157'],
);

const BookDetails _bookDetails = BookDetails(
  key: '/works/OL27448W',
  title: 'The Lord of the Rings',
  description: 'A quest to destroy a ring.',
  firstPublishYear: 1954,
  coverId: 8231856,
  pageCount: 1216,
  isbns: ['9780618640157'],
);

Future<void> _pumpSearch(
  WidgetTester tester, {
  required TmdbClient tmdb,
  MediaRepository? repository,
  SettingsProvider? settings,
  OpenLibraryClient? books,
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
      openLibraryClient: books ?? _FakeOpenLibrary(),
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
    expect(
      find.text('Search for movies, series and books by title.'),
      findsOneWidget,
    );
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

    expect(find.text('Add to watchlist'), findsOneWidget);
    expect(find.text('148 min'), findsOneWidget);

    await tester.tap(find.text('Add to watchlist'));
    await tester.pumpAndSettle();

    expect(repository.insertCount, 1);
    expect(find.text('Already in your library'), findsOneWidget);
    expect(find.text('Add to watchlist'), findsNothing);
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
    expect(find.text('Add to watchlist'), findsNothing);
  });

  testWidgets('German UI queries TMDB with de-DE', (tester) async {
    final tmdb = _FakeTmdb(results: const [_hit]);
    await _pumpSearch(tester, tmdb: tmdb, settings: SettingsProvider());

    expect(find.text('Finde etwas zum Verfolgen'), findsOneWidget);
    expect(find.text('Filme, Serien und Bücher suchen'), findsOneWidget);
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

    expect(find.text('Zur Watchlist'), findsOneWidget);
    expect(find.text('148 Min.'), findsOneWidget);
  });

  testWidgets('switching language re-queries TMDB with the new code', (
    tester,
  ) async {
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

  // ───────────────────────────────────────────────────────────────────────────
  // books (OpenLibrary)
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('the Books scope lists OpenLibrary hits with a Book badge', (
    tester,
  ) async {
    final books = _FakeOpenLibrary(results: const [_bookHit]);
    await _pumpSearch(
      tester,
      tmdb: _FakeTmdb(results: const [_hit]),
      books: books,
    );

    // Switch to the Books scope before searching.
    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'herr der ringe');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(books.queries, ['herr der ringe']);
    expect(find.text('The Lord of the Rings'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('1954'), findsOneWidget);
    // The author teaser is shown for books.
    expect(find.text('by J.R.R. Tolkien'), findsOneWidget);
  });

  testWidgets('the Books scope never queries TMDB', (tester) async {
    final tmdb = _FakeTmdb(results: const [_hit]);
    final books = _FakeOpenLibrary(results: const [_bookHit]);
    await _pumpSearch(tester, tmdb: tmdb, books: books);

    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lotr');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(tmdb.queries, isEmpty);
    expect(books.queries, ['lotr']);
  });

  testWidgets('the All scope merges TMDB and book hits', (tester) async {
    final books = _FakeOpenLibrary(results: const [_bookHit]);
    await _pumpSearch(
      tester,
      tmdb: _FakeTmdb(results: const [_hit]),
      books: books,
    );

    await tester.enterText(find.byType(TextField), 'ring');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(books.queries, ['ring']);
    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('The Lord of the Rings'), findsOneWidget);
  });

  testWidgets('German scope labels are localized', (tester) async {
    await _pumpSearch(tester, tmdb: _FakeTmdb(), settings: SettingsProvider());

    expect(find.text('Alle'), findsOneWidget);
    expect(find.text('Bücher'), findsOneWidget);
  });

  testWidgets('German UI asks OpenLibrary for German ranking', (tester) async {
    final books = _FakeOpenLibrary(results: const [_bookHit]);
    await _pumpSearch(
      tester,
      tmdb: _FakeTmdb(),
      books: books,
      settings: SettingsProvider(),
    );

    await tester.enterText(find.byType(TextField), 'herr');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(books.languages, [AppLanguage.de]);
  });

  testWidgets('the book detail sheet adds the work to the library', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final books = _FakeOpenLibrary(
      results: const [_bookHit],
      details: _bookDetails,
    );
    await _pumpSearch(
      tester,
      tmdb: _FakeTmdb(),
      books: books,
      repository: repository,
    );

    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lotr');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    await tester.tap(find.text('The Lord of the Rings'));
    await tester.pumpAndSettle();

    expect(find.text('A quest to destroy a ring.'), findsOneWidget);
    expect(find.text('1216 pages'), findsOneWidget);
    expect(find.text('Add to watchlist'), findsOneWidget);

    await tester.tap(find.text('Add to watchlist'));
    await tester.pumpAndSettle();

    expect(repository.insertCount, 1);
    final item = repository.lastInserted!;
    expect(item.kind, MediaKind.book);
    expect(item.externalSource, 'openlibrary');
    expect(item.externalId, '/works/OL27448W');
    expect(item.authors, ['J.R.R. Tolkien']);
    expect(item.totalPages, 1216);
    expect(item.isbn, '9780618640157');
    expect(item.status, MediaStatus.planned);
    expect(find.text('Already in your library'), findsOneWidget);
  });

  testWidgets('an already tracked book shows as already in the library', (
    tester,
  ) async {
    final repository = _FakeRepository(
      existing: const MediaItem(
        id: 'existing',
        kind: MediaKind.book,
        title: 'The Lord of the Rings',
        externalSource: 'openlibrary',
        externalId: '/works/OL27448W',
      ),
    );
    await _pumpSearch(
      tester,
      tmdb: _FakeTmdb(),
      books: _FakeOpenLibrary(results: const [_bookHit], details: _bookDetails),
      repository: repository,
    );

    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lotr');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    await tester.tap(find.text('The Lord of the Rings'));
    await tester.pumpAndSettle();

    expect(find.text('Already in your library'), findsOneWidget);
    expect(find.text('Add to watchlist'), findsNothing);
  });

  testWidgets('a failing book search surfaces the OpenLibrary message', (
    tester,
  ) async {
    final books = _FakeOpenLibrary(
      searchError: 'Could not reach OpenLibrary. Check your connection.',
    );
    await _pumpSearch(tester, tmdb: _FakeTmdb(), books: books);

    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lotr');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(find.text('Search failed'), findsOneWidget);
    expect(
      find.text('Could not reach OpenLibrary. Check your connection.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // ISBN text search (phase 6a)
  // ───────────────────────────────────────────────────────────────────────────

  const String validIsbn = '978-0-306-40615-7';
  const String normalizedIsbn = '9780306406157';

  testWidgets('the search field hints that an ISBN can be typed', (
    tester,
  ) async {
    await _pumpSearch(tester, tmdb: _FakeTmdb());
    expect(find.text('Tip: you can also enter an ISBN.'), findsOneWidget);
  });

  testWidgets('a valid ISBN runs the ISBN lookup on the Books scope', (
    tester,
  ) async {
    final tmdb = _FakeTmdb(results: const [_hit]);
    final books = _FakeOpenLibrary(
      results: const [_bookHit],
      isbnResult: _bookHit,
    );
    await _pumpSearch(tester, tmdb: tmdb, books: books);

    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), validIsbn);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    // The normalized ISBN was looked up, the title search was skipped.
    expect(books.isbnQueries, [normalizedIsbn]);
    expect(books.queries, isEmpty);
    // The lookup marker is visible.
    expect(find.text('ISBN lookup'), findsOneWidget);
    // The hit renders like any other book hit.
    expect(find.text('The Lord of the Rings'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('by J.R.R. Tolkien'), findsOneWidget);
  });

  testWidgets('the All scope runs the ISBN lookup and never queries TMDB', (
    tester,
  ) async {
    final tmdb = _FakeTmdb(results: const [_hit]);
    final books = _FakeOpenLibrary(
      results: const [_bookHit],
      isbnResult: _bookHit,
    );
    await _pumpSearch(tester, tmdb: tmdb, books: books);

    await tester.enterText(find.byType(TextField), validIsbn);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(books.isbnQueries, [normalizedIsbn]);
    expect(tmdb.queries, isEmpty);
    expect(find.text('ISBN lookup'), findsOneWidget);
    expect(find.text('The Lord of the Rings'), findsOneWidget);
  });

  testWidgets('the ISBN lookup gets the active app language', (tester) async {
    final books = _FakeOpenLibrary(isbnResult: _bookHit);
    await _pumpSearch(
      tester,
      tmdb: _FakeTmdb(),
      books: books,
      settings: SettingsProvider(), // German
    );

    await tester.enterText(find.byType(TextField), validIsbn);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(books.isbnLanguages, [AppLanguage.de]);
  });

  testWidgets('a number with a broken check digit is a normal search', (
    tester,
  ) async {
    final tmdb = _FakeTmdb();
    final books = _FakeOpenLibrary();
    await _pumpSearch(tester, tmdb: tmdb, books: books);

    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();

    // Valid length, wrong check digit → not an ISBN → plain title search.
    await tester.enterText(find.byType(TextField), '9780306406158');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(books.isbnQueries, isEmpty);
    expect(books.queries, ['9780306406158']);
    expect(find.text('ISBN lookup'), findsNothing);
  });

  testWidgets('the Movies scope ignores an ISBN and searches TMDB', (
    tester,
  ) async {
    final tmdb = _FakeTmdb(results: const [_hit]);
    final books = _FakeOpenLibrary(isbnResult: _bookHit);
    await _pumpSearch(tester, tmdb: tmdb, books: books);

    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), validIsbn);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(books.isbnQueries, isEmpty);
    expect(tmdb.queries, [validIsbn]);
    expect(find.text('ISBN lookup'), findsNothing);
  });

  testWidgets('an ISBN without a hit shows the localized not-found message', (
    tester,
  ) async {
    final books = _FakeOpenLibrary(); // isbnResult == null → not found
    await _pumpSearch(tester, tmdb: _FakeTmdb(), books: books);

    await tester.enterText(find.byType(TextField), validIsbn);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(books.isbnQueries, [normalizedIsbn]);
    expect(find.text('No book found for this ISBN'), findsOneWidget);
    expect(find.textContaining(normalizedIsbn), findsOneWidget);
    // Not the generic "no results" state.
    expect(find.text('No results'), findsNothing);
  });

  testWidgets('a failing ISBN lookup surfaces the OpenLibrary message', (
    tester,
  ) async {
    final books = _FakeOpenLibrary(
      isbnError: 'Could not reach OpenLibrary. Check your connection.',
    );
    await _pumpSearch(tester, tmdb: _FakeTmdb(), books: books);

    await tester.enterText(find.byType(TextField), validIsbn);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(find.text('Search failed'), findsOneWidget);
    expect(
      find.text('Could not reach OpenLibrary. Check your connection.'),
      findsOneWidget,
    );
  });

  testWidgets('the book detail sheet adds an ISBN hit to the library', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final books = _FakeOpenLibrary(
      results: const [_bookHit],
      details: _bookDetails,
      isbnResult: _bookHit,
    );
    await _pumpSearch(
      tester,
      tmdb: _FakeTmdb(),
      books: books,
      repository: repository,
    );

    await tester.enterText(find.byType(TextField), validIsbn);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    await tester.tap(find.text('The Lord of the Rings'));
    await tester.pumpAndSettle();

    expect(find.text('Add to watchlist'), findsOneWidget);
    expect(find.text('1216 pages'), findsOneWidget);

    await tester.tap(find.text('Add to watchlist'));
    await tester.pumpAndSettle();

    expect(repository.insertCount, 1);
    final item = repository.lastInserted!;
    expect(item.kind, MediaKind.book);
    expect(item.externalSource, 'openlibrary');
    // Work-level key so the add dedups against a later title search.
    expect(item.externalId, '/works/OL27448W');
    expect(find.text('Already in your library'), findsOneWidget);
  });

  testWidgets('German ISBN UI is localized', (tester) async {
    final books = _FakeOpenLibrary(); // not found
    await _pumpSearch(
      tester,
      tmdb: _FakeTmdb(),
      books: books,
      settings: SettingsProvider(),
    );

    expect(
      find.text('Tipp: Du kannst auch eine ISBN eingeben.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), validIsbn);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(find.text('ISBN-Suche'), findsOneWidget);
    expect(find.text('Kein Buch zu dieser ISBN gefunden'), findsOneWidget);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // two add actions: "Add to watchlist" vs "Mark as watched"
  // ───────────────────────────────────────────────────────────────────────────

  group('add as watched from a search hit', () {
    const String watched = 'Mark as watched';

    Future<void> openHit(
      WidgetTester tester,
      String query,
      String title,
    ) async {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    testWidgets('a movie hit offers both actions', (tester) async {
      await _pumpSearch(tester, tmdb: _FakeTmdb(results: const [_hit]));
      await openHit(tester, 'inception', 'Inception');

      expect(find.text('Add to watchlist'), findsOneWidget);
      expect(find.text(watched), findsOneWidget);
    });

    testWidgets('a movie is added completed at 100 %', (tester) async {
      final repository = _FakeRepository();
      await _pumpSearch(
        tester,
        tmdb: _FakeTmdb(results: const [_hit]),
        repository: repository,
      );
      await openHit(tester, 'inception', 'Inception');

      await tester.tap(find.text(watched));
      await tester.pumpAndSettle();

      expect(repository.insertCount, 1);
      final fields = repository.trackingWrites.last;
      expect(fields['status'], 'completed');
      expect(fields['progress_percent'], 100);
      expect(fields['completed_at'], isNotNull);
      expect(find.text('Marked as watched'), findsOneWidget);
    });

    testWidgets('a book is completed and logs the full page jump', (
      tester,
    ) async {
      final repository = _FakeRepository();
      await _pumpSearch(
        tester,
        tmdb: _FakeTmdb(),
        books: _FakeOpenLibrary(
          results: const [_bookHit],
          details: _bookDetails,
        ),
        repository: repository,
      );
      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      await openHit(tester, 'lotr', 'The Lord of the Rings');

      await tester.tap(find.text(watched));
      await tester.pumpAndSettle();

      final fields = repository.trackingWrites.last;
      expect(fields['status'], 'completed');
      expect(fields['progress_percent'], 100);
      expect(fields['progress_current'], 1216);
      // The page jump goes through the reading-log funnel, not a direct write.
      expect(repository.readingLogs, hasLength(1));
      expect(repository.readingLogs.single['pages'], 1216);
      expect(find.text('Marked as watched'), findsOneWidget);
    });

    testWidgets('a series loads its episodes and marks them all watched', (
      tester,
    ) async {
      final repository = _FakeRepository(episodes: _episodesFor('new-id', 3));
      await _pumpSearch(
        tester,
        tmdb: _FakeTmdb(
          results: const [_tvHit],
          tvSeasons: const <int, int>{1: 3},
        ),
        repository: repository,
      );
      await openHit(tester, 'lost', 'Lost');

      await tester.tap(find.text(watched));
      await tester.pumpAndSettle();

      expect(repository.insertCount, 1);
      expect(repository.episodes.every((e) => e.watched), isTrue);
      final fields = repository.trackingWrites.last;
      expect(fields['status'], 'completed');
      expect(fields['progress_percent'], 100);
      expect(find.text('Marked as watched'), findsOneWidget);
    });

    testWidgets('a failed episode load keeps the series in the watchlist', (
      tester,
    ) async {
      final repository = _FakeRepository();
      await _pumpSearch(
        tester,
        tmdb: _FakeTmdb(results: const [_tvHit], failTv: true),
        repository: repository,
      );
      await openHit(tester, 'lost', 'Lost');

      await tester.tap(find.text(watched));
      await tester.pumpAndSettle();

      expect(repository.insertCount, 1);
      // Deliberately kept as `planned` — never a half-finished "completed".
      expect(repository.lastInserted?.status, MediaStatus.planned);
      expect(repository.trackingWrites, isEmpty);
      expect(
        find.text(
          'Could not load the episodes. The item stays in your watchlist.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an already tracked entry shows no actions', (tester) async {
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
      await openHit(tester, 'inception', 'Inception');

      expect(find.text('Already in your library'), findsOneWidget);
      expect(find.text('Add to watchlist'), findsNothing);
      expect(find.text(watched), findsNothing);
    });
  });
}
