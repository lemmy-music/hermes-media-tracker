import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:media_tracker/main.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/models/tmdb_result.dart';
import 'package:media_tracker/providers/auth_provider.dart';
import 'package:media_tracker/providers/theme_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/services/tmdb_client.dart';

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

  @override
  bool get hasToken => enabled;

  @override
  Future<List<TmdbSearchResult>> search(
    String query, {
    TmdbSearchScope scope = TmdbSearchScope.all,
    int page = 1,
  }) async {
    queries.add(query);
    final error = searchError;
    if (error != null) throw TmdbException(error);
    return results;
  }

  @override
  Future<TmdbDetails> fetchDetails(TmdbSearchResult result) async {
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
}) async {
  await tester.pumpWidget(
    MediaTrackerApp(
      themeProvider: ThemeProvider(),
      authProvider: _FakeAuth(),
      repository: repository ?? _FakeRepository(),
      tmdbClient: tmdb,
    ),
  );
  await tester.pump();
  // Switch to the Search tab.
  await tester.tap(find.text('Search'));
  await tester.pumpAndSettle();
}

void main() {
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
}
