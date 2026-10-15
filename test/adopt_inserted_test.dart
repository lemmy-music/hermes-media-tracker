import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/models/episode.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/providers/library_provider.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/services/tmdb_client.dart';
import 'package:media_tracker/widgets/detail_sheets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// fakes — no network, no Supabase
// ─────────────────────────────────────────────────────────────────────────────

/// Repository stub with an in-memory library + episode store; every write is
/// recorded so the derived series state can be asserted.
class _FakeRepository extends MediaRepository {
  _FakeRepository({
    this.library = const <MediaItem>[],
    List<Episode> episodes = const <Episode>[],
  }) : episodes = List<Episode>.of(episodes);

  /// What [fetchAll] serves.
  List<MediaItem> library;

  List<Episode> episodes;

  int fetchCount = 0;
  MediaItem? lastInserted;
  final List<Map<String, dynamic>> trackingWrites = <Map<String, dynamic>>[];

  @override
  Future<List<MediaItem>> fetchAll() async {
    fetchCount++;
    return library;
  }

  @override
  Future<MediaItem> insert(MediaItem item) async {
    lastInserted = item;
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

class _FakeTmdb extends TmdbClient {
  _FakeTmdb()
    : super(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        token: 'fake',
      );
}

LibraryProvider _provider(MediaRepository repository) => LibraryProvider(
  repository: repository,
  tmdbClient: _FakeTmdb(),
  settings: SettingsProvider(initial: AppLanguage.en),
);

MediaItem _series() => const MediaItem(
  kind: MediaKind.series,
  title: 'Lost',
  externalSource: 'tmdb',
  externalId: '9001',
);

MediaItem _existingMovie({
  String id = 'a',
  String tmdbId = '1',
  String title = 'Inception',
  MediaStatus status = MediaStatus.planned,
}) => MediaItem(
  id: id,
  kind: MediaKind.movie,
  title: title,
  externalSource: 'tmdb',
  externalId: tmdbId,
  status: status,
);

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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('LibraryProvider.adoptInserted', () {
    test('adds a freshly stored item and indexes it immediately', () async {
      final repository = _FakeRepository();
      final provider = _provider(repository);
      await provider.load();

      const item = MediaItem(
        id: 'new',
        kind: MediaKind.movie,
        title: 'Inception',
        externalSource: 'tmdb',
        externalId: '27205',
      );
      provider.adoptInserted(item);

      expect(provider.items, <MediaItem>[item]);
      // The badge index knows the title at once — no reload required.
      expect(provider.lookup('tmdb', '27205'), item);
      expect(provider.badgeState('tmdb', '27205').inLibrary, isTrue);
      expect(provider.badgeStateForIdentity(item.identityKey).watched, isFalse);
      // Adopting never triggered a second load.
      expect(repository.fetchCount, 1);
    });

    test(
      'updates an existing item in place instead of duplicating it',
      () async {
        final existing = _existingMovie();
        final repository = _FakeRepository(library: <MediaItem>[existing]);
        final provider = _provider(repository);
        await provider.load();
        expect(provider.items, hasLength(1));

        provider.adoptInserted(
          existing.copyWith(status: MediaStatus.completed),
        );

        expect(provider.items, hasLength(1));
        expect(provider.itemById('a')?.status, MediaStatus.completed);
        expect(provider.lookup('tmdb', '1')?.status, MediaStatus.completed);
      },
    );

    test('matches by external identity when the local id differs', () async {
      final provider = _provider(_FakeRepository());
      await provider.load();

      provider.adoptInserted(_existingMovie(id: 'a', title: 'Inception'));
      // Same title, different local id (e.g. a re-inserted row).
      provider.adoptInserted(_existingMovie(id: 'b', title: 'Inception (neu)'));

      expect(provider.items, hasLength(1));
      expect(provider.itemById('a'), isNull);
      expect(provider.itemById('b')?.title, 'Inception (neu)');
      expect(provider.lookup('tmdb', '1')?.id, 'b');
    });

    test('does not adopt into a library that was never loaded', () async {
      final repository = _FakeRepository();
      final provider = _provider(repository);

      provider.adoptInserted(
        const MediaItem(
          id: 'new',
          kind: MediaKind.movie,
          title: 'Inception',
          externalSource: 'tmdb',
          externalId: '27205',
        ),
      );

      // Nothing adopted synchronously…
      expect(provider.items, isEmpty);
      expect(provider.lookup('tmdb', '27205'), isNull);

      // …but a one-time load was kicked off instead (which serves an empty
      // library here, so the list stays empty — never a one-entry list).
      await pumpEventQueue();
      expect(repository.fetchCount, 1);
      expect(provider.items, isEmpty);
    });
  });

  group('insertAsWatched adopts the final state', () {
    test('a movie ends up completed with no reload', () async {
      final repository = _FakeRepository();
      final provider = _provider(repository);
      await provider.load();

      final outcome = await insertAsWatched(
        repository,
        provider,
        const MediaItem(
          kind: MediaKind.movie,
          title: 'Inception',
          externalSource: 'tmdb',
          externalId: '27205',
        ),
      );

      expect(outcome.result, AddAsWatchedResult.done);
      expect(outcome.item.status, MediaStatus.completed);
      expect(outcome.item.progressPercent, 100);
      // The item is already in the in-memory library, completed.
      expect(provider.itemById('new-id')?.status, MediaStatus.completed);
      expect(provider.lookup('tmdb', '27205')?.status, MediaStatus.completed);
      // No reload — the only fetchAll is the initial one.
      expect(repository.fetchCount, 1);
    });

    test('a series adopts the derived status and progress', () async {
      final repository = _FakeRepository(episodes: _episodesFor('new-id', 3));
      final provider = _provider(repository);
      await provider.load();

      final outcome = await insertAsWatched(repository, provider, _series());

      expect(outcome.result, AddAsWatchedResult.done);
      // 3/3 episodes watched → derived completed + 100 %.
      expect(outcome.item.status, MediaStatus.completed);
      expect(outcome.item.progressPercent, 100);
      final stored = provider.itemById('new-id');
      expect(stored?.status, MediaStatus.completed);
      expect(stored?.progressPercent, 100);
      expect(provider.badgeState('tmdb', '9001').watched, isTrue);
      // The episode automation ran through the normal paths.
      expect(repository.trackingWrites.last['status'], 'completed');
      expect(repository.trackingWrites.last['progress_percent'], 100);
      expect(repository.fetchCount, 1);
    });

    test(
      'a series without loadable episodes keeps the watchlist state',
      () async {
        final repository = _FakeRepository();
        final provider = _provider(repository);
        await provider.load();

        final outcome = await insertAsWatched(repository, provider, _series());

        expect(outcome.result, AddAsWatchedResult.keepInWatchlist);
        expect(outcome.item.status, MediaStatus.planned);
        // Adopted as planned so it is visible immediately.
        expect(provider.itemById('new-id')?.status, MediaStatus.planned);
        expect(provider.lookup('tmdb', '9001')?.status, MediaStatus.planned);
        // The episode loader may persist its derived 0 %, but nothing may claim
        // the series is completed.
        expect(
          repository.trackingWrites.any(
            (fields) => fields['status'] == MediaStatus.completed.wire,
          ),
          isFalse,
        );
        expect(repository.fetchCount, 1);
      },
    );
  });
}
