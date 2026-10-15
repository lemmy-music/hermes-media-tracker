import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/models/book_result.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/models/tmdb_result.dart';
import 'package:media_tracker/providers/library_provider.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/services/tmdb_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// fakes (no network, no Supabase)
// ─────────────────────────────────────────────────────────────────────────────

/// Repository stub: a fixed library list plus a configurable load failure.
class _FakeRepository extends MediaRepository {
  _FakeRepository({
    List<MediaItem> items = const <MediaItem>[],
    this.failLoad = false,
  }) : _items = List<MediaItem>.of(items);

  List<MediaItem> _items;

  /// When `true`, [fetchAll] throws a [MediaRepositoryException].
  final bool failLoad;

  int fetchCount = 0;
  final List<String> deletedIds = <String>[];

  /// Swap the backing list (used to prove the index is rebuilt on reload).
  set items(List<MediaItem> value) => _items = List<MediaItem>.of(value);

  @override
  Future<List<MediaItem>> fetchAll() async {
    fetchCount++;
    if (failLoad) {
      throw const MediaRepositoryException('Could not load your library.');
    }
    return _items;
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    _items = _items.where((item) => item.id != id).toList();
  }

  @override
  Future<MediaItem> updateTracking(
    String id,
    Map<String, dynamic> fields,
  ) async {
    final base = _items.firstWhere((item) => item.id == id);
    final row = Map<String, dynamic>.from(base.toMap())
      ..['id'] = id
      ..addAll(fields);
    final updated = MediaItem.fromMap(row);
    _items = <MediaItem>[
      for (final item in _items)
        if (item.id == id) updated else item,
    ];
    return updated;
  }
}

/// Minimal TMDB stub — [LibraryProvider] only needs a non-null client here.
class _FakeTmdb extends TmdbClient {
  _FakeTmdb()
    : super(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        token: 'fake',
      );

  @override
  bool get hasToken => true;
}

LibraryProvider _provider(_FakeRepository repository) => LibraryProvider(
  repository: repository,
  tmdbClient: _FakeTmdb(),
  settings: SettingsProvider(initial: AppLanguage.en),
);

MediaItem _item({
  required String id,
  required String source,
  required String externalId,
  MediaStatus status = MediaStatus.planned,
}) => MediaItem(
  id: id,
  kind: source == kExternalSourceOpenLibrary ? MediaKind.book : MediaKind.movie,
  title: 'Title $id',
  externalSource: source,
  externalId: externalId,
  status: status,
);

void main() {
  group('mediaIdentity — the single identity key', () {
    test('joins a source and id with a colon', () {
      expect(mediaIdentity('tmdb', '27205'), 'tmdb:27205');
      expect(
        mediaIdentity('openlibrary', '/works/OL27448W'),
        'openlibrary:/works/OL27448W',
      );
    });

    test('returns null when either part is missing or empty', () {
      expect(mediaIdentity(null, '27205'), isNull);
      expect(mediaIdentity('tmdb', null), isNull);
      expect(mediaIdentity('', '27205'), isNull);
      expect(mediaIdentity('tmdb', ''), isNull);
      expect(mediaIdentity(null, null), isNull);
    });
  });

  group('search-hit identity keys match the stored values', () {
    test('TMDB movie hit', () {
      const hit = TmdbSearchResult(
        id: 27205,
        type: TmdbMediaType.movie,
        title: 'Inception',
      );
      expect(hit.identityKey, 'tmdb:27205');
      expect(hit.identityKey, mediaIdentity(kExternalSourceTmdb, '27205'));
    });

    test('TMDB series hit — and its stored item agree', () {
      const hit = TmdbSearchResult(
        id: 9001,
        type: TmdbMediaType.tv,
        title: 'Lost',
      );
      expect(hit.identityKey, 'tmdb:9001');

      final stored = const TmdbTvDetails(id: 9001, name: 'Lost').toMediaItem();
      expect(stored.identityKey, hit.identityKey);
    });

    test('TMDB movie details store the matching external_id', () {
      final item = const TmdbMovieDetails(
        id: 27205,
        title: 'Inception',
      ).toMediaItem();
      expect(item.externalSource, 'tmdb');
      expect(item.externalId, '27205');
      expect(item.identityKey, 'tmdb:27205');
    });

    test('OpenLibrary work hit — and its stored item agree', () {
      const hit = BookResult(key: '/works/OL27448W', title: 'The Lord …');
      expect(hit.identityKey, 'openlibrary:/works/OL27448W');
      expect(hit.toMediaItem().identityKey, hit.identityKey);
    });

    test('an ISBN lookup resolves to the work key, matching a title search', () {
      // `OpenLibraryClient.lookupByIsbn` returns a BookResult whose key is the
      // linked work key — exactly the shape a title search yields.
      const isbnResolved = BookResult(
        key: '/works/OL27448W',
        title: 'The Lord of the Rings',
        isbns: ['9780618640157'],
      );
      const titleSearch = BookResult(
        key: '/works/OL27448W',
        title: 'The Lord of the Rings',
      );
      expect(isbnResolved.identityKey, titleSearch.identityKey);

      // The stored row (external_id = work key) matches both.
      final stored = isbnResolved.toMediaItem();
      expect(stored.externalSource, 'openlibrary');
      expect(stored.externalId, '/works/OL27448W');
      expect(stored.identityKey, isbnResolved.identityKey);
    });

    test('a manual item without an external source has no identity', () {
      const item = MediaItem(kind: MediaKind.movie, title: 'Manual');
      expect(item.identityKey, isNull);
    });
  });

  group('LibraryProvider index', () {
    test('lookup finds tracked entries and misses untracked ones', () async {
      final provider = _provider(
        _FakeRepository(
          items: <MediaItem>[
            _item(id: 'm', source: kExternalSourceTmdb, externalId: '27205'),
            _item(
              id: 'b',
              source: kExternalSourceOpenLibrary,
              externalId: '/works/OL27448W',
            ),
          ],
        ),
      );
      await provider.load();

      expect(provider.lookup('tmdb', '27205'), isNotNull);
      expect(provider.lookup('openlibrary', '/works/OL27448W'), isNotNull);
      expect(provider.lookup('tmdb', '404'), isNull);
      expect(provider.lookup(null, null), isNull);
      expect(provider.lookupIdentity('tmdb:27205'), isNotNull);
      expect(provider.lookupIdentity('tmdb:404'), isNull);
      expect(provider.lookupIdentity(null), isNull);
    });

    test(
      'badgeState: inLibrary for any status, watched only when completed',
      () async {
        final provider = _provider(
          _FakeRepository(
            items: <MediaItem>[
              _item(
                id: 'planned',
                source: kExternalSourceTmdb,
                externalId: '1',
                status: MediaStatus.planned,
              ),
              _item(
                id: 'progress',
                source: kExternalSourceTmdb,
                externalId: '2',
                status: MediaStatus.inProgress,
              ),
              _item(
                id: 'dropped',
                source: kExternalSourceTmdb,
                externalId: '3',
                status: MediaStatus.dropped,
              ),
              _item(
                id: 'done',
                source: kExternalSourceTmdb,
                externalId: '4',
                status: MediaStatus.completed,
              ),
            ],
          ),
        );
        await provider.load();

        expect(provider.badgeState('tmdb', '1'), (
          inLibrary: true,
          watched: false,
        ));
        expect(provider.badgeState('tmdb', '2'), (
          inLibrary: true,
          watched: false,
        ));
        expect(provider.badgeState('tmdb', '3'), (
          inLibrary: true,
          watched: false,
        ));
        expect(provider.badgeState('tmdb', '4'), (
          inLibrary: true,
          watched: true,
        ));
        // Nothing tracked → no badges at all.
        expect(provider.badgeState('tmdb', '404'), (
          inLibrary: false,
          watched: false,
        ));
        expect(provider.badgeStateForIdentity('tmdb:4'), (
          inLibrary: true,
          watched: true,
        ));
        expect(provider.badgeStateForIdentity('tmdb:404'), (
          inLibrary: false,
          watched: false,
        ));
      },
    );

    test('the index is rebuilt when the list changes', () async {
      final repository = _FakeRepository(
        items: <MediaItem>[
          _item(
            id: 'a',
            source: kExternalSourceTmdb,
            externalId: '10',
            status: MediaStatus.completed,
          ),
        ],
      );
      final provider = _provider(repository);
      await provider.load();
      expect(provider.badgeState('tmdb', '10').watched, isTrue);

      // A status change through the tracking funnel updates the index at once.
      await provider.setStatus(
        provider.lookup('tmdb', '10')!,
        MediaStatus.planned,
      );
      expect(provider.badgeState('tmdb', '10'), (
        inLibrary: true,
        watched: false,
      ));

      // A reload with a different list replaces the entries.
      repository.items = <MediaItem>[
        _item(id: 'z', source: kExternalSourceTmdb, externalId: '99'),
      ];
      await provider.load();
      expect(provider.lookup('tmdb', '10'), isNull);
      expect(provider.lookup('tmdb', '99'), isNotNull);
    });

    test('a deleted item disappears from the index', () async {
      final provider = _provider(
        _FakeRepository(
          items: <MediaItem>[
            _item(id: 'a', source: kExternalSourceTmdb, externalId: '10'),
          ],
        ),
      );
      await provider.load();
      expect(provider.badgeState('tmdb', '10').inLibrary, isTrue);

      await provider.deleteItem(provider.lookup('tmdb', '10')!);
      expect(provider.badgeState('tmdb', '10'), (
        inLibrary: false,
        watched: false,
      ));
    });
  });

  group('LibraryProvider.ensureLoaded', () {
    test('triggers the load exactly once', () async {
      final repository = _FakeRepository();
      final provider = _provider(repository);

      await provider.ensureLoaded();
      await provider.ensureLoaded();
      expect(repository.fetchCount, 1);
    });

    test('is a no-op when a load already happened', () async {
      final repository = _FakeRepository();
      final provider = _provider(repository);
      await provider.load();
      expect(repository.fetchCount, 1);

      await provider.ensureLoaded();
      expect(repository.fetchCount, 1);
    });

    test('a failed load never throws and yields no badges', () async {
      final provider = _provider(_FakeRepository(failLoad: true));

      await expectLater(provider.ensureLoaded(), completes);
      expect(provider.badgeState('tmdb', '1'), (
        inLibrary: false,
        watched: false,
      ));
    });
  });
}
