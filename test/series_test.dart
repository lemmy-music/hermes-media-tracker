import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/models/episode.dart';
import 'package:media_tracker/models/json_utils.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/models/tmdb_result.dart';
import 'package:media_tracker/providers/library_provider.dart';
import 'package:media_tracker/providers/series_rules.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/services/tmdb_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// fakes / helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Series metadata stub — records what was fetched, never hits the network.
class _FakeSeriesTmdb extends TmdbClient {
  _FakeSeriesTmdb({
    this.episodesBySeason = const <int, int>{1: 3},
    this.failSeasons = const <int>{},
  }) : super(
         httpClient: MockClient((_) async => http.Response('{}', 200)),
         token: 'fake',
       );

  final Map<int, int> episodesBySeason;
  final Set<int> failSeasons;

  int fetchTvCount = 0;
  final List<String> detailsLanguages = <String>[];
  final List<int> seasonCalls = <int>[];
  final List<String> seasonLanguages = <String>[];

  @override
  Future<TmdbTvDetails> fetchTv(int id, {String? language}) async {
    fetchTvCount++;
    detailsLanguages.add(language ?? '<none>');
    final seasons = episodesBySeason.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return TmdbTvDetails(
      id: id,
      name: 'Lost',
      originalName: 'Lost',
      year: 2004,
      numberOfSeasons: episodesBySeason.length,
      numberOfEpisodes: episodesBySeason.values.fold<int>(0, (a, b) => a + b),
      seasons: [
        for (final entry in seasons)
          TmdbSeasonSummary(
            seasonNumber: entry.key,
            name: 'Season ${entry.key}',
            episodeCount: entry.value,
          ),
      ],
    );
  }

  @override
  Future<TmdbSeasonDetails> fetchSeason(
    int tvId,
    int seasonNumber, {
    String? language,
  }) async {
    seasonCalls.add(seasonNumber);
    seasonLanguages.add(language ?? '<none>');
    if (failSeasons.contains(seasonNumber)) {
      throw const TmdbException('TMDB request failed.');
    }
    final count = episodesBySeason[seasonNumber] ?? 0;
    return TmdbSeasonDetails(
      seasonNumber: seasonNumber,
      name: 'Season $seasonNumber',
      episodes: [
        for (var i = 1; i <= count; i++)
          TmdbEpisode(
            episodeNumber: i,
            name: 'Neu $i',
            airDate: DateTime.utc(2004, 9, i),
            runtime: 42,
          ),
      ],
    );
  }
}

/// In-memory repository with an episode store, recording every write.
class _FakeRepo extends MediaRepository {
  _FakeRepo({
    this.items = const <MediaItem>[],
    List<Episode> episodes = const [],
  }) : episodes = List<Episode>.of(episodes);

  List<MediaItem> items;
  List<Episode> episodes;

  final List<Map<String, dynamic>> trackingWrites = [];
  final List<List<Episode>> episodeMetadataUpserts = [];
  final List<MediaItem> metadataUpdates = [];
  final List<String> watchedCalls = [];
  int episodeFetchCount = 0;

  @override
  Future<List<MediaItem>> fetchAll() async => List<MediaItem>.of(items);

  @override
  Future<MediaItem> updateMetadata(MediaItem item) async {
    metadataUpdates.add(item);
    final index = items.indexWhere((candidate) => candidate.id == item.id);
    if (index != -1) items[index] = item;
    return item;
  }

  @override
  Future<MediaItem> updateTracking(
    String id,
    Map<String, dynamic> fields,
  ) async {
    trackingWrites.add(fields);
    final index = items.indexWhere((item) => item.id == id);
    final row = Map<String, dynamic>.from(items[index].toMap())..addAll(fields);
    final updated = MediaItem.fromMap(row);
    items[index] = updated;
    return updated;
  }

  @override
  Future<List<Episode>> fetchEpisodes(String mediaItemId) async {
    episodeFetchCount++;
    return episodes
        .where((episode) => episode.mediaItemId == mediaItemId)
        .toList()
      ..sort((a, b) {
        final bySeason = a.seasonNumber.compareTo(b.seasonNumber);
        return bySeason != 0
            ? bySeason
            : a.episodeNumber.compareTo(b.episodeNumber);
      });
  }

  @override
  Future<List<Episode>> upsertEpisodeMetadata(List<Episode> incoming) async {
    episodeMetadataUpserts.add(incoming);
    final saved = <Episode>[];
    for (final episode in incoming) {
      final index = episodes.indexWhere(
        (candidate) =>
            candidate.mediaItemId == episode.mediaItemId &&
            candidate.seasonNumber == episode.seasonNumber &&
            candidate.episodeNumber == episode.episodeNumber,
      );
      final stored = Episode(
        id: index == -1
            ? 'ep-${episode.seasonNumber}-${episode.episodeNumber}'
            : episodes[index].id,
        mediaItemId: episode.mediaItemId,
        seasonNumber: episode.seasonNumber,
        episodeNumber: episode.episodeNumber,
        name: episode.name,
        overview: episode.overview,
        airDate: episode.airDate,
        stillUrl: episode.stillUrl,
        runtime: episode.runtime,
        // Watch state is preserved from the stored row (metadata-only write).
        watched: index == -1 ? false : episodes[index].watched,
        watchedAt: index == -1 ? null : episodes[index].watchedAt,
        createdAt: index == -1 ? null : episodes[index].createdAt,
      );
      if (index == -1) {
        episodes.add(stored);
      } else {
        episodes[index] = stored;
      }
      saved.add(stored);
    }
    return saved;
  }

  @override
  Future<List<Episode>> upsertEpisodes(List<Episode> incoming) =>
      upsertEpisodeMetadata(incoming);

  @override
  Future<Episode> setWatched(String episodeId, bool watched) async {
    watchedCalls.add('$episodeId:$watched');
    final index = episodes.indexWhere((episode) => episode.id == episodeId);
    final stored = _copyWatched(episodes[index], watched);
    episodes[index] = stored;
    return stored;
  }

  @override
  Future<List<Episode>> markSeasonWatched(
    String mediaItemId,
    int seasonNumber,
  ) async => _setSeason(mediaItemId, seasonNumber, watched: true);

  @override
  Future<List<Episode>> resetSeason(
    String mediaItemId,
    int seasonNumber,
  ) async => _setSeason(mediaItemId, seasonNumber, watched: false);

  List<Episode> _setSeason(
    String mediaItemId,
    int seasonNumber, {
    required bool watched,
  }) {
    final updated = <Episode>[];
    for (var i = 0; i < episodes.length; i++) {
      final episode = episodes[i];
      if (episode.mediaItemId != mediaItemId ||
          episode.seasonNumber != seasonNumber) {
        continue;
      }
      final stored = _copyWatched(episode, watched);
      episodes[i] = stored;
      updated.add(stored);
    }
    return updated;
  }

  Episode _copyWatched(Episode episode, bool watched) => Episode(
    id: episode.id,
    mediaItemId: episode.mediaItemId,
    seasonNumber: episode.seasonNumber,
    episodeNumber: episode.episodeNumber,
    name: episode.name,
    overview: episode.overview,
    airDate: episode.airDate,
    stillUrl: episode.stillUrl,
    runtime: episode.runtime,
    watched: watched,
    watchedAt: watched ? DateTime.utc(2026, 1, 1) : null,
    createdAt: episode.createdAt,
  );
}

MediaItem _series({
  String id = 'series-1',
  MediaStatus status = MediaStatus.planned,
  double? percent,
  DateTime? startedAt,
  DateTime? completedAt,
  String? externalId = '42',
}) => MediaItem(
  id: id,
  kind: MediaKind.series,
  title: 'Lost',
  status: status,
  progressPercent: percent,
  startedAt: startedAt,
  completedAt: completedAt,
  externalSource: externalId == null ? null : 'tmdb',
  externalId: externalId,
);

List<Episode> _storedEpisodes(int count, {int watched = 0}) => [
  for (var i = 1; i <= count; i++)
    Episode(
      id: 'ep-1-$i',
      mediaItemId: 'series-1',
      seasonNumber: 1,
      episodeNumber: i,
      name: 'Folge $i',
      airDate: DateTime.utc(2004, 9, i),
      watched: i <= watched,
      watchedAt: i <= watched ? DateTime.utc(2026, 1, 1) : null,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
];

LibraryProvider _provider(
  _FakeRepo repository,
  TmdbClient tmdb, {
  AppLanguage language = AppLanguage.en,
  DateTime? now,
}) => LibraryProvider(
  repository: repository,
  tmdbClient: tmdb,
  settings: SettingsProvider(initial: language),
  clock: now == null ? null : () => now,
);

// ── PostgREST-level helpers ──────────────────────────────────────────────────

Map<String, dynamic> _episodeRow({int id = 1, bool watched = false}) =>
    <String, dynamic>{
      'id': 'ep-$id',
      'media_item_id': 'item-1',
      'season_number': 1,
      'episode_number': id,
      'name': 'Pilot',
      'overview': 'x',
      'air_date': '2004-09-01',
      'still_url': null,
      'runtime': 42,
      'watched': watched,
      'watched_at': watched ? '2026-01-01T00:00:00.000Z' : null,
      'created_at': '2026-01-01T00:00:00.000Z',
    };

List<Map<String, dynamic>> _requestBodyList(http.Request request) {
  final decoded = jsonDecode(request.body);
  if (decoded is List) {
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  return <Map<String, dynamic>>[Map<String, dynamic>.from(decoded as Map)];
}

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

  final now = DateTime.utc(2026, 5, 1, 12);

  group('seriesProgressPercent', () {
    test('rounds to one decimal', () {
      expect(seriesProgressPercent(10, 19), 52.6);
      expect(seriesProgressPercent(1, 3), 33.3);
      expect(seriesProgressPercent(1, 8), 12.5);
      expect(seriesProgressPercent(2, 4), 50.0);
    });

    test('clamps and guards against a zero total', () {
      expect(seriesProgressPercent(0, 10), 0);
      expect(seriesProgressPercent(10, 10), 100);
      expect(seriesProgressPercent(20, 10), 100);
      expect(seriesProgressPercent(5, 0), 0);
      expect(seriesProgressPercent(-1, 10), 0);
    });
  });

  group('seriesDerivedFields', () {
    test('nothing watched leaves the status untouched', () {
      final fields = seriesDerivedFields(
        _series(status: MediaStatus.completed),
        watchedCount: 0,
        totalCount: 10,
      );
      expect(fields['progress_percent'], 0);
      expect(fields.containsKey('status'), isFalse);
      expect(fields.containsKey('started_at'), isFalse);
      expect(fields.containsKey('completed_at'), isFalse);
    });

    test('a partial watch sets in_progress and stamps started_at', () {
      final fields = seriesDerivedFields(
        _series(),
        watchedCount: 5,
        totalCount: 10,
        now: now,
      );
      expect(fields['progress_percent'], 50);
      expect(fields['status'], 'in_progress');
      expect(fields['started_at'], isoDateTime(now));
      expect(fields.containsKey('completed_at'), isFalse);
    });

    test('watching everything completes and stamps completed_at', () {
      final fields = seriesDerivedFields(
        _series(),
        watchedCount: 10,
        totalCount: 10,
        now: now,
      );
      expect(fields['progress_percent'], 100);
      expect(fields['status'], 'completed');
      expect(fields['started_at'], isoDateTime(now));
      expect(fields['completed_at'], isoDateTime(now));
    });

    test('manual timestamps are never overwritten', () {
      final fields = seriesDerivedFields(
        _series(
          startedAt: DateTime.utc(2020, 1, 1),
          completedAt: DateTime.utc(2021, 1, 1),
        ),
        watchedCount: 10,
        totalCount: 10,
        now: now,
      );
      expect(fields.containsKey('started_at'), isFalse);
      expect(fields.containsKey('completed_at'), isFalse);
    });

    test('dropped is never set nor removed by the automation', () {
      final partial = seriesDerivedFields(
        _series(status: MediaStatus.dropped),
        watchedCount: 5,
        totalCount: 10,
        now: now,
      );
      expect(partial.containsKey('status'), isFalse);
      expect(partial['progress_percent'], 50);

      final all = seriesDerivedFields(
        _series(status: MediaStatus.dropped),
        watchedCount: 10,
        totalCount: 10,
        now: now,
      );
      expect(all.containsKey('status'), isFalse);
      expect(all['progress_percent'], 100);
    });

    test('a series without episodes never completes', () {
      final fields = seriesDerivedFields(
        _series(),
        watchedCount: 0,
        totalCount: 0,
        now: now,
      );
      expect(fields, <String, dynamic>{'progress_percent': 0});
    });
  });

  group('episode metadata payload', () {
    test('covers exactly the metadata columns, never the watch state', () {
      final payload = episodeMetadataPayload(
        _storedEpisodes(1, watched: 1).single,
      );
      expect(payload.keys.toSet(), kEpisodeMetadataFields);
      expect(kEpisodeMetadataFields, <String>{
        'media_item_id',
        'season_number',
        'episode_number',
        'name',
        'overview',
        'air_date',
        'still_url',
        'runtime',
      });
      for (final forbidden in const <String>[
        'id',
        'user_id',
        'watched',
        'watched_at',
        'created_at',
      ]) {
        expect(payload.containsKey(forbidden), isFalse, reason: forbidden);
      }
      expect(payload['air_date'], '2004-09-01');
    });
  });

  group('MediaRepository episodes', () {
    Future<MediaRepository> repository(List<http.Request> requests) async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-anon-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          // `.single()` requests an object; list selects get an array.
          final wantsObject = (request.headers['accept'] ?? '').contains(
            'pgrst.object',
          );
          final body = wantsObject
              ? jsonEncode(_episodeRow())
              : jsonEncode(<Map<String, dynamic>>[_episodeRow()]);
          return http.Response(
            body,
            200,
            request: request,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      await _recoverSession(client);
      return MediaRepository(client);
    }

    test('upsertEpisodeMetadata never sends the watch state', () async {
      final requests = <http.Request>[];
      final repo = await repository(requests);

      await repo.upsertEpisodeMetadata(_storedEpisodes(2, watched: 1));

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, contains('episodes'));
      final body = _requestBodyList(requests.single);
      expect(body, hasLength(2));
      for (final row in body) {
        expect(row.keys.toSet(), kEpisodeMetadataFields.union({'user_id'}));
        expect(row.containsKey('watched'), isFalse);
        expect(row.containsKey('watched_at'), isFalse);
      }
    });

    test('setWatched stamps and clears watched_at', () async {
      final requests = <http.Request>[];
      final repo = await repository(requests);

      await repo.setWatched('ep-1', true);
      final watchedBody = _requestBodyList(requests.last).single;
      expect(watchedBody['watched'], isTrue);
      expect(watchedBody['watched_at'], isNotNull);

      await repo.setWatched('ep-1', false);
      final unwatchedBody = _requestBodyList(requests.last).single;
      expect(unwatchedBody['watched'], isFalse);
      expect(unwatchedBody['watched_at'], isNull);
    });

    test('markSeasonWatched updates the whole season', () async {
      final requests = <http.Request>[];
      final repo = await repository(requests);

      await repo.markSeasonWatched('item-1', 2);

      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.path, contains('episodes'));
      expect(request.url.queryParameters['media_item_id'], 'eq.item-1');
      expect(request.url.queryParameters['season_number'], 'eq.2');
      final body = _requestBodyList(request).single;
      expect(body['watched'], isTrue);
      expect(body['watched_at'], isNotNull);
    });

    test('resetSeason clears the watched state of the season', () async {
      final requests = <http.Request>[];
      final repo = await repository(requests);

      await repo.resetSeason('item-1', 3);

      expect(requests.single.url.queryParameters['season_number'], 'eq.3');
      expect(_requestBodyList(requests.single).single, <String, dynamic>{
        'watched': false,
        'watched_at': null,
      });
    });
  });

  group('LibraryProvider.ensureEpisodes (lazy load)', () {
    test(
      'first call loads from TMDB and persists, second is a no-op',
      () async {
        final repo = _FakeRepo(items: [_series()]);
        final tmdb = _FakeSeriesTmdb(episodesBySeason: {0: 2, 1: 3, 2: 4});
        final provider = _provider(repo, tmdb, now: now);
        await provider.load();

        await provider.ensureEpisodes(provider.items.single);

        expect(tmdb.fetchTvCount, 1);
        // Specials (season 0) are skipped; seasons 1 and 2 are fetched.
        expect(tmdb.seasonCalls, <int>[1, 2]);
        // All seasons are persisted in a single metadata-only upsert.
        expect(repo.episodeMetadataUpserts, hasLength(1));
        expect(repo.episodeMetadataUpserts.single, hasLength(7));
        expect(repo.episodes, hasLength(7));
        expect(provider.episodesFor('series-1'), hasLength(7));
        expect(provider.seasonsFor('series-1'), <int>[1, 2]);
        // The derived (empty) progress was persisted.
        expect(repo.trackingWrites.last['progress_percent'], 0);

        await provider.ensureEpisodes(provider.items.single);
        expect(tmdb.fetchTvCount, 1);
        expect(repo.episodeFetchCount, 1);
      },
    );

    test('stored episodes are used without touching TMDB', () async {
      final repo = _FakeRepo(
        items: [_series()],
        episodes: _storedEpisodes(4, watched: 2),
      );
      final tmdb = _FakeSeriesTmdb();
      final provider = _provider(repo, tmdb, now: now);
      await provider.load();

      await provider.ensureEpisodes(provider.items.single);

      expect(tmdb.fetchTvCount, 0);
      expect(tmdb.seasonCalls, isEmpty);
      expect(provider.episodesFor('series-1'), hasLength(4));
      // 2 of 4 watched → 50 %, in_progress.
      expect(repo.trackingWrites.last['progress_percent'], 50);
      expect(repo.trackingWrites.last['status'], 'in_progress');
    });

    test('a complete stored series is marked completed', () async {
      final repo = _FakeRepo(
        items: [_series()],
        episodes: _storedEpisodes(3, watched: 3),
      );
      final provider = _provider(repo, _FakeSeriesTmdb(), now: now);
      await provider.load();

      await provider.ensureEpisodes(provider.items.single);

      expect(repo.trackingWrites.last['progress_percent'], 100);
      expect(repo.trackingWrites.last['status'], 'completed');
      expect(repo.trackingWrites.last['completed_at'], isoDateTime(now));
    });

    test('a non-TMDB series loads nothing but does not retry', () async {
      final repo = _FakeRepo(items: [_series(externalId: null)]);
      final tmdb = _FakeSeriesTmdb();
      final provider = _provider(repo, tmdb);
      await provider.load();

      await provider.ensureEpisodes(provider.items.single);

      expect(tmdb.fetchTvCount, 0);
      expect(provider.episodesFor('series-1'), isEmpty);
      expect(provider.episodesError('series-1'), isNull);
    });
  });

  group('LibraryProvider episode mutations', () {
    test('setEpisodeWatched persists and derives the progress', () async {
      final repo = _FakeRepo(items: [_series()], episodes: _storedEpisodes(4));
      final provider = _provider(repo, _FakeSeriesTmdb(), now: now);
      await provider.load();
      await provider.ensureEpisodes(provider.items.single);

      await provider.setEpisodeWatched(
        provider.items.single,
        provider.episodesFor('series-1').first,
        true,
      );

      expect(repo.watchedCalls, ['ep-1-1:true']);
      expect(repo.trackingWrites.last['progress_percent'], 25);
      expect(repo.trackingWrites.last['status'], 'in_progress');
      expect(provider.episodesFor('series-1').first.watched, isTrue);
    });

    test('markSeasonWatched completes the series', () async {
      final repo = _FakeRepo(items: [_series()], episodes: _storedEpisodes(4));
      final provider = _provider(repo, _FakeSeriesTmdb(), now: now);
      await provider.load();
      await provider.ensureEpisodes(provider.items.single);

      await provider.markSeasonWatched(provider.items.single, 1);

      expect(repo.trackingWrites.last['progress_percent'], 100);
      expect(repo.trackingWrites.last['status'], 'completed');
      expect(provider.episodesFor('series-1').every((e) => e.watched), isTrue);
    });

    test(
      'resetSeason clears the watched state without touching dropped',
      () async {
        final repo = _FakeRepo(
          items: [_series(status: MediaStatus.dropped)],
          episodes: _storedEpisodes(4, watched: 4),
        );
        final provider = _provider(repo, _FakeSeriesTmdb(), now: now);
        await provider.load();
        await provider.ensureEpisodes(provider.items.single);

        await provider.resetSeason(provider.items.single, 1);

        expect(repo.trackingWrites.last['progress_percent'], 0);
        expect(repo.trackingWrites.last.containsKey('status'), isFalse);
        expect(
          provider.episodesFor('series-1').every((e) => !e.watched),
          isTrue,
        );
      },
    );

    test('dropped is kept when every episode is watched', () async {
      final repo = _FakeRepo(
        items: [_series(status: MediaStatus.dropped)],
        episodes: _storedEpisodes(4),
      );
      final provider = _provider(repo, _FakeSeriesTmdb(), now: now);
      await provider.load();
      await provider.ensureEpisodes(provider.items.single);

      await provider.markSeasonWatched(provider.items.single, 1);

      expect(repo.trackingWrites.last['progress_percent'], 100);
      expect(repo.trackingWrites.last.containsKey('status'), isFalse);
      expect(provider.itemById('series-1')?.status, MediaStatus.dropped);
    });
  });

  group('LibraryProvider.refreshMetadata (episodes)', () {
    test('refreshes the stored episodes in the new language', () async {
      final repo = _FakeRepo(
        items: [_series()],
        episodes: _storedEpisodes(3, watched: 1),
      );
      final tmdb = _FakeSeriesTmdb(episodesBySeason: const <int, int>{1: 3});
      final provider = _provider(repo, tmdb, now: now);
      await provider.load();

      final result = await provider.refreshMetadata(language: AppLanguage.de);

      expect(result.updated, 1);
      expect(tmdb.detailsLanguages, <String>['de-DE']);
      expect(tmdb.seasonLanguages, everyElement('de-DE'));
      // The stored episodes were re-fetched in German.
      expect(repo.episodeMetadataUpserts, hasLength(1));
      expect(repo.episodes.first.name, 'Neu 1');
      // …and the watch state survived.
      expect(repo.episodes.first.watched, isTrue);
      expect(repo.episodes.first.watchedAt, isNotNull);
    });

    test('a failing season does not abort the run or fail the item', () async {
      final repo = _FakeRepo(
        items: [_series()],
        episodes: _storedEpisodes(3, watched: 1),
      );
      final tmdb = _FakeSeriesTmdb(
        episodesBySeason: const <int, int>{1: 3},
        failSeasons: const <int>{1},
      );
      final provider = _provider(repo, tmdb, now: now);
      await provider.load();

      final result = await provider.refreshMetadata(language: AppLanguage.de);

      expect(result.updated, 1);
      expect(result.failed, 0);
      // No episode write happened, but the item itself was refreshed.
      expect(repo.episodeMetadataUpserts, isEmpty);
      expect(repo.episodes.first.watched, isTrue);
    });

    test('a series without episodes is not fetched during a refresh', () async {
      final repo = _FakeRepo(items: [_series()]);
      final tmdb = _FakeSeriesTmdb();
      final provider = _provider(repo, tmdb, now: now);
      await provider.load();

      await provider.refreshMetadata(language: AppLanguage.de);

      expect(tmdb.seasonCalls, isEmpty);
      expect(repo.episodeMetadataUpserts, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // bulk catch-up rules + write paths (Feature: "Massen-Nachtrag")
  // ───────────────────────────────────────────────────────────────────────────

  group('catch-up rules', () {
    Episode ep(int season, int number, {bool watched = false}) => Episode(
      id: 'ep-$season-$number',
      mediaItemId: 'series-1',
      seasonNumber: season,
      episodeNumber: number,
      watched: watched,
    );

    test('lists only earlier, still-unwatched episodes of the same season', () {
      final episodes = [
        ep(1, 1),
        ep(1, 2, watched: true),
        ep(1, 3),
        ep(1, 4, watched: true),
      ];

      final previous = previousUnwatchedEpisodes(episodes, ep(1, 4));

      expect(previous.map((e) => e.episodeNumber), <int>[1, 3]);
    });

    test('ignores later episodes and never reaches into earlier seasons', () {
      final episodes = [ep(1, 9), ep(2, 1), ep(2, 2), ep(2, 3)];

      final previous = previousUnwatchedEpisodes(episodes, ep(2, 3));

      expect(previous.map((e) => e.episodeNumber), <int>[1, 2]);
      // Season 1's open episode is deliberately out of scope (documented).
      expect(previous.every((e) => e.seasonNumber == 2), isTrue);
    });

    test('is empty when nothing earlier is still open (no prompt)', () {
      final episodes = [ep(1, 1, watched: true), ep(1, 2, watched: true)];

      expect(previousUnwatchedEpisodes(episodes, ep(1, 2)), isEmpty);
    });

    test('the first episode of a season has no earlier episodes', () {
      final episodes = [ep(1, 1), ep(1, 2)];

      expect(previousUnwatchedEpisodes(episodes, ep(1, 1)), isEmpty);
    });

    test('seasons with open episodes are collected once, ascending', () {
      final episodes = [
        ep(1, 1),
        ep(1, 2),
        ep(2, 1),
        ep(2, 2, watched: true),
        ep(3, 1),
      ];

      expect(previousSeasonsWithUnwatched(episodes, 3), <int>[1, 2]);
    });

    test('the first / only season never prompts', () {
      final episodes = [ep(1, 1), ep(1, 2), ep(2, 1)];

      expect(previousSeasonsWithUnwatched(episodes, 1), isEmpty);
      expect(previousSeasonsWithUnwatched(<Episode>[ep(1, 1)], 1), isEmpty);
    });

    test('fully watched earlier seasons never prompt', () {
      final episodes = [
        ep(1, 1, watched: true),
        ep(1, 2, watched: true),
        ep(2, 1),
      ];

      expect(previousSeasonsWithUnwatched(episodes, 2), isEmpty);
    });
  });

  group('LibraryProvider catch-up writes', () {
    List<Episode> twoSeasons() => [
      for (var i = 1; i <= 3; i++)
        Episode(
          id: 'ep-1-$i',
          mediaItemId: 'series-1',
          seasonNumber: 1,
          episodeNumber: i,
        ),
      for (var i = 1; i <= 2; i++)
        Episode(
          id: 'ep-2-$i',
          mediaItemId: 'series-1',
          seasonNumber: 2,
          episodeNumber: i,
        ),
    ];

    test(
      'markEpisodesWatched stamps every episode and derives progress',
      () async {
        final repo = _FakeRepo(items: [_series()], episodes: twoSeasons());
        final provider = _provider(repo, _FakeSeriesTmdb(), now: now);
        await provider.load();
        await provider.ensureEpisodes(provider.items.single);

        final all = provider.episodesFor('series-1');
        final target = all.firstWhere(
          (e) => e.seasonNumber == 2 && e.episodeNumber == 2,
        );
        final previous = previousUnwatchedEpisodes(all, target);
        await provider.setEpisodeWatched(provider.items.single, target, true);
        await provider.markEpisodesWatched(provider.items.single, previous);

        // The tapped episode first, then the earlier one it caught up.
        expect(repo.watchedCalls, <String>['ep-2-2:true', 'ep-2-1:true']);
        expect(
          provider.episodesFor('series-1').where((e) => e.watched).length,
          2,
        );
        expect(repo.trackingWrites.last['progress_percent'], 40);
        expect(repo.trackingWrites.last['status'], 'in_progress');
      },
    );

    test(
      'markSeasonWatched(includePreviousSeasons) completes the series',
      () async {
        final repo = _FakeRepo(items: [_series()], episodes: twoSeasons());
        final provider = _provider(repo, _FakeSeriesTmdb(), now: now);
        await provider.load();
        await provider.ensureEpisodes(provider.items.single);

        await provider.markSeasonWatched(
          provider.items.single,
          2,
          includePreviousSeasons: true,
        );

        expect(
          provider.episodesFor('series-1').every((e) => e.watched),
          isTrue,
        );
        expect(repo.trackingWrites.last['progress_percent'], 100);
        expect(repo.trackingWrites.last['status'], 'completed');
        expect(repo.trackingWrites.last['completed_at'], isoDateTime(now));
      },
    );

    test('without the flag earlier seasons stay untouched', () async {
      final repo = _FakeRepo(items: [_series()], episodes: twoSeasons());
      final provider = _provider(repo, _FakeSeriesTmdb(), now: now);
      await provider.load();
      await provider.ensureEpisodes(provider.items.single);

      await provider.markSeasonWatched(provider.items.single, 2);

      final seasonOne = provider
          .episodesFor('series-1')
          .where((e) => e.seasonNumber == 1);
      expect(seasonOne.every((e) => !e.watched), isTrue);
      expect(repo.trackingWrites.last['progress_percent'], 40);
      expect(repo.trackingWrites.last['status'], 'in_progress');
    });

    test('markAllEpisodesWatched marks every season', () async {
      final repo = _FakeRepo(items: [_series()], episodes: twoSeasons());
      final provider = _provider(repo, _FakeSeriesTmdb(), now: now);
      await provider.load();
      await provider.ensureEpisodes(provider.items.single);

      await provider.markAllEpisodesWatched(provider.items.single);

      expect(provider.episodesFor('series-1').every((e) => e.watched), isTrue);
      expect(repo.trackingWrites.last['progress_percent'], 100);
      expect(repo.trackingWrites.last['status'], 'completed');
    });
  });
}
