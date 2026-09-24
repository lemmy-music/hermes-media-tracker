import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/main.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/models/tmdb_result.dart';
import 'package:media_tracker/providers/auth_provider.dart';
import 'package:media_tracker/providers/library_provider.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/providers/theme_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/services/tmdb_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// fakes
// ─────────────────────────────────────────────────────────────────────────────

/// Metadata client stub — no network. Records the requested ids/languages and
/// can fail selected TMDB ids to exercise the robustness of a refresh run.
class _FakeTmdb extends TmdbClient {
  _FakeTmdb({this.failingIds = const <int>{}})
    : super(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        token: 'fake',
      );

  /// TMDB ids whose details request throws.
  final Set<int> failingIds;

  final List<int> requestedIds = [];

  /// The `language` argument of every [fetchDetails] call.
  final List<String> languages = [];

  @override
  Future<TmdbDetails> fetchDetails(
    TmdbSearchResult result, {
    String? language,
  }) async {
    requestedIds.add(result.id);
    languages.add(language ?? '<none>');
    if (failingIds.contains(result.id)) {
      throw const TmdbException('TMDB request failed.');
    }
    if (result.type == TmdbMediaType.tv) {
      return TmdbTvDetails(
        id: result.id,
        name: '${result.title} (neu)',
        originalName: result.originalTitle,
        year: 2011,
        numberOfSeasons: 8,
        numberOfEpisodes: 73,
        overview: 'Überblick ${result.id}',
      );
    }
    return TmdbMovieDetails(
      id: result.id,
      title: '${result.title} (neu)',
      originalTitle: result.originalTitle,
      year: 2001,
      overview: 'Überblick ${result.id}',
    );
  }
}

/// Repository stub: an in-memory library plus a recording [updateMetadata].
class _FakeRepository extends MediaRepository {
  _FakeRepository({
    this.items = const <MediaItem>[],
    this.failingUpdateIds = const <String>{},
  });

  List<MediaItem> items;

  /// Item ids whose [updateMetadata] write fails.
  final Set<String> failingUpdateIds;

  final List<Map<String, dynamic>> metadataUpdatePayloads = [];
  final List<String> updatedIds = [];
  int fetchCount = 0;

  @override
  Future<List<MediaItem>> fetchAll() async {
    fetchCount++;
    return items;
  }

  @override
  Future<MediaItem> updateMetadata(MediaItem item) async {
    final id = item.id!;
    if (failingUpdateIds.contains(id)) {
      throw const MediaRepositoryException('Could not refresh the metadata.');
    }
    metadataUpdatePayloads.add(metadataUpdatePayload(item));
    updatedIds.add(id);
    return item;
  }
}

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

// ─────────────────────────────────────────────────────────────────────────────
// helpers
// ─────────────────────────────────────────────────────────────────────────────

MediaItem _tmdbMovie(
  String id, {
  required int tmdbId,
  String title = 'Movie',
  MediaKind kind = MediaKind.movie,
}) => MediaItem(
  id: id,
  kind: kind,
  title: title,
  status: MediaStatus.inProgress,
  progressPercent: 40,
  progressCurrent: 2,
  externalSource: 'tmdb',
  externalId: '$tmdbId',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 2),
);

LibraryProvider _provider({
  required MediaRepository repository,
  required TmdbClient tmdbClient,
  AppLanguage language = AppLanguage.de,
  int maxConcurrency = LibraryProvider.defaultMaxConcurrency,
}) => LibraryProvider(
  repository: repository,
  tmdbClient: tmdbClient,
  settings: SettingsProvider(initial: language),
  maxConcurrency: maxConcurrency,
);

Map<String, dynamic> _storedRow() => <String, dynamic>{
  'id': 'item-1',
  'kind': 'movie',
  'title': 'Der Herr der Ringe',
  'original_title': 'The Lord of the Rings',
  'release_year': 2001,
  'overview': 'Ein Ring…',
  'poster_url': 'https://image.tmdb.org/t/p/w342/x.jpg',
  'external_source': 'tmdb',
  'external_id': '120',
  'authors': <dynamic>[],
  'total_seasons': 1,
  'total_episodes': 3,
  'status': 'in_progress',
  'progress_percent': 40,
  'progress_current': 4,
  'started_at': null,
  'completed_at': null,
  'created_at': '2026-01-01T00:00:00.000Z',
  'updated_at': '2026-02-01T00:00:00.000Z',
};

/// Decodes a PostgREST write body — supabase-dart sends the payload either as
/// a bare object or wrapped in a single-element array.
Map<String, dynamic> _requestBody(http.Request request) {
  final decoded = jsonDecode(request.body);
  if (decoded is List) {
    return Map<String, dynamic>.from(decoded.single as Map);
  }
  return Map<String, dynamic>.from(decoded as Map);
}

/// Signs a [SupabaseClient] in without a backend so `currentUser` is set.
Future<void> _recoverSession(SupabaseClient client) {
  return client.auth.recoverSession(
    jsonEncode(<String, dynamic>{
      'access_token': 'access-token',
      'refresh_token': 'refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000,
      'user': <String, dynamic>{
        'id': 'user-1',
        'aud': 'authenticated',
        'role': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00.000Z',
      },
    }),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('MediaRepository.updateMetadata', () {
    test('sends exactly the 7 metadata fields, no tracking state', () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-anon-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(_storedRow()),
            200,
            request: request,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      await _recoverSession(client);

      final repository = MediaRepository(client);
      final stored = await repository.updateMetadata(
        MediaItem(
          id: 'item-1',
          kind: MediaKind.movie,
          title: 'Der Herr der Ringe',
          originalTitle: 'The Lord of the Rings',
          releaseYear: 2001,
          overview: 'Ein Ring…',
          posterUrl: 'https://image.tmdb.org/t/p/w342/x.jpg',
          totalSeasons: 1,
          totalEpisodes: 3,
          // Deliberately set — none of these may reach the request body.
          status: MediaStatus.completed,
          progressPercent: 100,
          progressCurrent: 9,
          startedAt: null,
          completedAt: null,
          createdAt: DateTime.utc(2025, 1, 1),
          updatedAt: DateTime.utc(2025, 6, 1),
        ),
      );

      expect(requests, hasLength(1));
      final body = _requestBody(requests.single);
      expect(body.keys.toSet(), kMetadataUpdateFields);
      expect(kMetadataUpdateFields, <String>{
        'title',
        'original_title',
        'release_year',
        'overview',
        'poster_url',
        'total_seasons',
        'total_episodes',
      });

      for (final forbidden in const <String>[
        'id',
        'user_id',
        'kind',
        'status',
        'progress_percent',
        'progress_current',
        'started_at',
        'completed_at',
        'created_at',
        'updated_at',
        'external_source',
        'external_id',
        'authors',
        'total_pages',
        'isbn',
      ]) {
        expect(body.containsKey(forbidden), isFalse, reason: forbidden);
      }

      expect(body['title'], 'Der Herr der Ringe');
      expect(body['original_title'], 'The Lord of the Rings');
      expect(body['release_year'], 2001);
      expect(body['overview'], 'Ein Ring…');
      expect(body['poster_url'], 'https://image.tmdb.org/t/p/w342/x.jpg');
      expect(body['total_seasons'], 1);
      expect(body['total_episodes'], 3);
      // The stored row is returned unchanged.
      expect(stored.title, 'Der Herr der Ringe');
    });
  });

  group('LibraryProvider.refreshMetadata', () {
    test('refreshes only TMDB items and counts updated/total', () async {
      final repository = _FakeRepository(
        items: [
          _tmdbMovie('a', tmdbId: 1, title: 'Inception'),
          _tmdbMovie('b', tmdbId: 2, title: 'Arrival'),
          const MediaItem(id: 'c', kind: MediaKind.book, title: 'Dune'),
          // An OpenLibrary book must not become a refresh candidate either:
          // OpenLibrary has no localized work metadata.
          const MediaItem(
            id: 'd',
            kind: MediaKind.book,
            title: 'Der Herr der Ringe',
            externalSource: 'openlibrary',
            externalId: '/works/OL27448W',
          ),
        ],
      );
      final tmdb = _FakeTmdb();
      final provider = _provider(
        repository: repository,
        tmdbClient: tmdb,
        maxConcurrency: 1,
      );
      await provider.load();

      final result = await provider.refreshMetadata(language: AppLanguage.de);

      expect(result.total, 2);
      expect(result.updated, 2);
      expect(result.failed, 0);
      expect(result.hadCandidates, isTrue);
      expect(result.hadFailures, isFalse);
      expect(tmdb.requestedIds..sort(), <int>[1, 2]);
      expect(tmdb.languages, everyElement('de-DE'));
      expect(repository.updatedIds..sort(), <String>['a', 'b']);
      // Neither book is ever sent to TMDB, and neither inflates the count.
      expect(tmdb.requestedIds, isNot(contains(3)));
      expect(repository.updatedIds, isNot(contains('d')));
    });

    test(
      'a failing request does not stop the others and counts as failed',
      () async {
        final repository = _FakeRepository(
          items: [
            _tmdbMovie('a', tmdbId: 1, title: 'Inception'),
            _tmdbMovie('b', tmdbId: 2, title: 'Arrival'),
            _tmdbMovie('c', tmdbId: 3, title: 'Dune'),
          ],
        );
        final tmdb = _FakeTmdb(failingIds: {2});
        final provider = _provider(
          repository: repository,
          tmdbClient: tmdb,
          maxConcurrency: 2,
        );
        await provider.load();

        final result = await provider.refreshMetadata(language: AppLanguage.de);

        expect(result.total, 3);
        expect(result.updated, 2);
        expect(result.failed, 1);
        expect(result.hadFailures, isTrue);
        // Every candidate was attempted…
        expect(tmdb.requestedIds..sort(), <int>[1, 2, 3]);
        // …but only the two successful ones were written.
        expect(repository.updatedIds..sort(), <String>['a', 'c']);
        expect(repository.updatedIds, isNot(contains('b')));
        // The failed item keeps its stored snapshot.
        final kept = provider.items.firstWhere((item) => item.id == 'b');
        expect(kept.title, 'Arrival');
      },
    );

    test(
      'a failing write keeps the old metadata and counts as failed',
      () async {
        final repository = _FakeRepository(
          items: [_tmdbMovie('a', tmdbId: 1, title: 'Inception')],
          failingUpdateIds: {'a'},
        );
        final provider = _provider(
          repository: repository,
          tmdbClient: _FakeTmdb(),
          maxConcurrency: 1,
        );
        await provider.load();

        final result = await provider.refreshMetadata(language: AppLanguage.de);

        expect(result.total, 1);
        expect(result.updated, 0);
        expect(result.failed, 1);
        expect(repository.updatedIds, isEmpty);
      },
    );

    test('an empty library reports nothing to refresh', () async {
      final provider = _provider(
        repository: _FakeRepository(),
        tmdbClient: _FakeTmdb(),
      );
      await provider.load();

      final result = await provider.refreshMetadata(language: AppLanguage.de);

      expect(result, isNotNull);
      expect(result.hadCandidates, isFalse);
      expect(result.updated, 0);
      expect(result.total, 0);
    });

    test('a language change triggers a refresh in the new language', () async {
      final repository = _FakeRepository(
        items: [_tmdbMovie('a', tmdbId: 1, title: 'Inception')],
      );
      final tmdb = _FakeTmdb();
      final settings = SettingsProvider(initial: AppLanguage.en);
      final provider = LibraryProvider(
        repository: repository,
        tmdbClient: tmdb,
        settings: settings,
      );
      await provider.load();

      expect(provider.metadataRefreshRuns, 0);

      await settings.setLanguage(AppLanguage.de);
      await pumpEventQueue();

      expect(tmdb.languages, <String>['de-DE']);
      expect(repository.updatedIds, <String>['a']);
      expect(provider.metadataRefreshRuns, 1);
      expect(provider.lastMetadataRefresh?.total, 1);
    });

    test('re-selecting the current language does not refresh', () async {
      final repository = _FakeRepository(
        items: [_tmdbMovie('a', tmdbId: 1, title: 'Inception')],
      );
      final tmdb = _FakeTmdb();
      final settings = SettingsProvider(initial: AppLanguage.en);
      final provider = LibraryProvider(
        repository: repository,
        tmdbClient: tmdb,
        settings: settings,
      );
      await provider.load();

      await settings.setLanguage(AppLanguage.en);
      await pumpEventQueue();

      expect(tmdb.requestedIds, isEmpty);
      expect(provider.metadataRefreshRuns, 0);
    });
  });

  group('language change UI', () {
    testWidgets('a language switch refreshes the library and reports it once', (
      tester,
    ) async {
      final repository = _FakeRepository(
        items: [
          _tmdbMovie('a', tmdbId: 1, title: 'Inception'),
          _tmdbMovie('b', tmdbId: 2, title: 'Arrival'),
          _tmdbMovie('c', tmdbId: 3, title: 'Dune'),
        ],
      );
      final tmdb = _FakeTmdb(failingIds: {3});
      final settings = SettingsProvider(initial: AppLanguage.en);

      await tester.pumpWidget(
        MediaTrackerApp(
          themeProvider: ThemeProvider(),
          settingsProvider: settings,
          authProvider: _FakeAuth(),
          repository: repository,
          tmdbClient: tmdb,
        ),
      );
      // Initial (automatic) library load.
      await tester.pump();
      await tester.pump();
      expect(find.text('Inception'), findsOneWidget);

      await settings.setLanguage(AppLanguage.de);
      await tester.pumpAndSettle();

      expect(tmdb.languages, everyElement('de-DE'));
      // Exactly one snack bar per completed run, localized to the new language.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text(
          '2 von 3 aktualisiert – 1 konnten nicht geladen werden. '
          'Die alten Angaben bleiben sichtbar.',
        ),
        findsOneWidget,
      );
    });
  });
}
