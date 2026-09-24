import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/models/json_utils.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/providers/library_provider.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/providers/tracking_rules.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/services/tmdb_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// fakes / helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Metadata client stub — never hits the network.
class _StubTmdb extends TmdbClient {
  _StubTmdb()
    : super(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        token: 'fake',
      );
}

/// Repository stub: an in-memory library that applies tracking writes exactly
/// like PostgREST would (row + payload → row).
class _FakeRepository extends MediaRepository {
  _FakeRepository(this.items, {this.failTracking = false});

  List<MediaItem> items;

  /// When `true`, [updateTracking] throws — to test error propagation.
  final bool failTracking;

  final List<Map<String, dynamic>> writes = [];
  final List<String> deleted = [];

  @override
  Future<List<MediaItem>> fetchAll() async => List<MediaItem>.of(items);

  @override
  Future<MediaItem> updateTracking(
    String id,
    Map<String, dynamic> fields,
  ) async {
    if (failTracking) {
      throw const MediaRepositoryException('Could not save the change.');
    }
    writes.add(fields);
    final index = items.indexWhere((item) => item.id == id);
    final row = Map<String, dynamic>.from(items[index].toMap())..addAll(fields);
    final updated = MediaItem.fromMap(row);
    items[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    items.removeWhere((item) => item.id == id);
  }
}

LibraryProvider _provider(_FakeRepository repository, {DateTime? now}) =>
    LibraryProvider(
      repository: repository,
      tmdbClient: _StubTmdb(),
      settings: SettingsProvider(initial: AppLanguage.en),
      clock: now == null ? null : () => now,
    );

MediaItem _movie({
  String id = 'm',
  String title = 'Inception',
  MediaStatus status = MediaStatus.planned,
  double? percent,
  int? current,
  DateTime? startedAt,
  DateTime? completedAt,
}) => MediaItem(
  id: id,
  kind: MediaKind.movie,
  title: title,
  status: status,
  progressPercent: percent,
  progressCurrent: current,
  startedAt: startedAt,
  completedAt: completedAt,
);

MediaItem _book({
  String id = 'b',
  String title = 'Dune',
  int? totalPages,
  MediaStatus status = MediaStatus.planned,
  double? percent,
  int? current,
  DateTime? completedAt,
}) => MediaItem(
  id: id,
  kind: MediaKind.book,
  title: title,
  totalPages: totalPages,
  status: status,
  progressPercent: percent,
  progressCurrent: current,
  completedAt: completedAt,
);

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

Map<String, dynamic> _storedRow() => <String, dynamic>{
  'id': 'item-1',
  'kind': 'movie',
  'title': 'Inception',
  'release_year': 2010,
  'external_source': 'tmdb',
  'external_id': '27205',
  'status': 'completed',
  'progress_percent': 100,
  'progress_current': null,
  'started_at': '2026-01-01T10:00:00.000Z',
  'completed_at': '2026-02-01T18:30:00.000Z',
  'created_at': '2026-01-01T00:00:00.000Z',
  'updated_at': '2026-02-01T00:00:00.000Z',
};

Map<String, dynamic> _requestBody(http.Request request) {
  final decoded = jsonDecode(request.body);
  if (decoded is List) {
    return Map<String, dynamic>.from(decoded.single as Map);
  }
  return Map<String, dynamic>.from(decoded as Map);
}

// ─────────────────────────────────────────────────────────────────────────────
// tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  final now = DateTime.utc(2026, 5, 1, 12);

  group('tracking columns', () {
    test('cover exactly the tracking state, never metadata', () {
      expect(kTrackingUpdateFields, <String>{
        'status',
        'progress_percent',
        'progress_current',
        'started_at',
        'completed_at',
        'total_pages',
      });
      for (final forbidden in const <String>[
        'id',
        'user_id',
        'kind',
        'title',
        'overview',
        'poster_url',
        'external_source',
        'external_id',
        'authors',
        'isbn',
        'total_seasons',
        'total_episodes',
        'created_at',
        'updated_at',
      ]) {
        expect(kTrackingUpdateFields.contains(forbidden), isFalse);
      }
    });
  });

  group('statusChangeFields', () {
    test('planned resets the progress and clears both timestamps', () {
      final fields = statusChangeFields(
        _movie(
          status: MediaStatus.completed,
          percent: 100,
          current: 9,
          startedAt: DateTime.utc(2024),
          completedAt: DateTime.utc(2025),
        ),
        MediaStatus.planned,
      );
      expect(fields, <String, dynamic>{
        'status': 'planned',
        'progress_percent': 0,
        'progress_current': null,
        'started_at': null,
        'completed_at': null,
      });
    });

    test('in_progress fills started_at only when it is empty', () {
      final filled = statusChangeFields(
        _movie(),
        MediaStatus.inProgress,
        now: now,
      );
      expect(filled['status'], 'in_progress');
      expect(filled['started_at'], isoDateTime(now));
      expect(filled.containsKey('completed_at'), isFalse);
      expect(filled.containsKey('progress_percent'), isFalse);
    });

    test('in_progress keeps a manually entered started_at', () {
      final fields = statusChangeFields(
        _movie(startedAt: DateTime.utc(2020, 1, 1)),
        MediaStatus.inProgress,
        now: now,
      );
      expect(fields.containsKey('started_at'), isFalse);
    });

    test('completed fills completed_at and forces 100 %', () {
      final fields = statusChangeFields(
        _movie(),
        MediaStatus.completed,
        now: now,
      );
      expect(fields['status'], 'completed');
      expect(fields['completed_at'], isoDateTime(now));
      expect(fields['progress_percent'], 100);
    });

    test('completed keeps a manually entered completed_at', () {
      final manual = DateTime.utc(2019, 3, 3);
      final fields = statusChangeFields(
        _movie(completedAt: manual),
        MediaStatus.completed,
        now: now,
      );
      expect(fields.containsKey('completed_at'), isFalse);
      expect(fields['progress_percent'], 100);
    });

    test('completed also finishes a known book page count', () {
      final fields = statusChangeFields(
        _book(totalPages: 300),
        MediaStatus.completed,
        now: now,
      );
      expect(fields['progress_percent'], 100);
      expect(fields['progress_current'], 300);
    });

    test('dropped only writes the status', () {
      final fields = statusChangeFields(
        _movie(status: MediaStatus.inProgress, percent: 20, current: 2),
        MediaStatus.dropped,
      );
      expect(fields, <String, dynamic>{'status': 'dropped'});
    });
  });

  group('progressPercentFields', () {
    test('100 % completes the item and stamps the time', () {
      final fields = progressPercentFields(
        _movie(status: MediaStatus.inProgress, percent: 50),
        100,
        now: now,
      );
      expect(fields['progress_percent'], 100);
      expect(fields['status'], 'completed');
      expect(fields['completed_at'], isoDateTime(now));
    });

    test('100 % leaves a dropped item dropped', () {
      final fields = progressPercentFields(
        _movie(status: MediaStatus.dropped, percent: 50),
        100,
        now: now,
      );
      expect(fields.containsKey('status'), isFalse);
      expect(fields.containsKey('completed_at'), isFalse);
    });

    test('keeps a known book page count in sync', () {
      final fields = progressPercentFields(_book(totalPages: 300), 50);
      expect(fields['progress_percent'], 50);
      expect(fields['progress_current'], 150);
    });

    test('a partial percent on a movie touches only the percent', () {
      final fields = progressPercentFields(_movie(), 42.5);
      expect(fields, <String, dynamic>{'progress_percent': 42.5});
    });
  });

  group('progressPageFields', () {
    test('derives the percent and completes on the last page', () {
      final fields = progressPageFields(
        _book(totalPages: 300, status: MediaStatus.inProgress),
        300,
        now: now,
      );
      expect(fields['progress_current'], 300);
      expect(fields['progress_percent'], 100);
      expect(fields['status'], 'completed');
      expect(fields['completed_at'], isoDateTime(now));
    });

    test('clamps a page beyond the total', () {
      final fields = progressPageFields(_book(totalPages: 300), 400);
      expect(fields['progress_current'], 300);
      expect(fields['progress_percent'], 100);
    });

    test('rounds the derived percent to two decimals', () {
      final fields = progressPageFields(_book(totalPages: 3), 1);
      expect(fields['progress_percent'], 33.33);
    });
  });

  group('totalPagesFields', () {
    test('recomputes the percent when a page is already known', () {
      final fields = totalPagesFields(
        _book(totalPages: 200, current: 50, percent: 25),
        100,
      );
      expect(fields['total_pages'], 100);
      expect(fields['progress_current'], 50);
      expect(fields['progress_percent'], 50);
    });

    test('writes only total_pages when no page is set', () {
      expect(totalPagesFields(_book(), 250), <String, dynamic>{
        'total_pages': 250,
      });
    });

    test('clears the page count for null / non-positive input', () {
      expect(
        totalPagesFields(_book(totalPages: 100), null)['total_pages'],
        null,
      );
      expect(totalPagesFields(_book(totalPages: 100), 0)['total_pages'], null);
    });
  });

  group('timestamp fields', () {
    test('serialise a value and clear with null', () {
      expect(startedAtFields(now), <String, dynamic>{
        'started_at': '2026-05-01T12:00:00.000Z',
      });
      expect(startedAtFields(null), <String, dynamic>{'started_at': null});
      expect(completedAtFields(null), <String, dynamic>{'completed_at': null});
    });
  });

  group('MediaRepository.updateTracking', () {
    test('PATCHes only the given tracking columns', () async {
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

      await repository.setStatus('item-1', MediaStatus.completed);

      expect(requests, hasLength(1));
      expect(requests.single.method, 'PATCH');
      expect(requests.single.url.path, contains('media_items'));
      final body = _requestBody(requests.single);
      expect(body, <String, dynamic>{'status': 'completed'});
      for (final forbidden in const <String>[
        'title',
        'overview',
        'poster_url',
        'kind',
        'progress_percent',
        'started_at',
        'completed_at',
        'total_pages',
      ]) {
        expect(body.containsKey(forbidden), isFalse, reason: forbidden);
      }
    });

    test('clears a timestamp with an explicit null', () async {
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

      await MediaRepository(client).setStartedAt('item-1', null);

      expect(_requestBody(requests.single), <String, dynamic>{
        'started_at': null,
      });
    });

    test('setTotalPages sends the page count', () async {
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

      await MediaRepository(client).setTotalPages('item-1', 250);

      expect(_requestBody(requests.single), <String, dynamic>{
        'total_pages': 250,
      });
    });

    test('refuses to write a non-tracking column', () async {
      await expectLater(
        MediaRepository().updateTracking('item-1', <String, dynamic>{
          'title': 'nope',
        }),
        throwsA(isA<MediaRepositoryException>()),
      );
    });
  });

  group('LibraryProvider tracking', () {
    test('setStatus persists and swaps the row into the list', () async {
      final repository = _FakeRepository([_movie()]);
      final provider = _provider(repository, now: now);
      await provider.load();

      await provider.setStatus(provider.items.single, MediaStatus.inProgress);

      expect(repository.writes.single['status'], 'in_progress');
      expect(repository.writes.single['started_at'], isoDateTime(now));
      expect(provider.items.single.status, MediaStatus.inProgress);
      expect(provider.items.single.startedAt, isNotNull);
    });

    test('progress reaching 100 % completes the item', () async {
      final repository = _FakeRepository([
        _movie(status: MediaStatus.inProgress),
      ]);
      final provider = _provider(repository, now: now);
      await provider.load();

      await provider.setProgressPercent(provider.items.single, 100);

      expect(repository.writes.single['progress_percent'], 100);
      expect(repository.writes.single['status'], 'completed');
      expect(provider.items.single.status, MediaStatus.completed);
    });

    test('a page update stores the derived percent', () async {
      final repository = _FakeRepository([_book(totalPages: 300)]);
      final provider = _provider(repository, now: now);
      await provider.load();

      await provider.setProgressPage(provider.items.single, 150);

      expect(repository.writes.single['progress_current'], 150);
      expect(repository.writes.single['progress_percent'], 50);
      expect(provider.items.single.progressCurrent, 150);
    });

    test('manual timestamps are written as-is', () async {
      final repository = _FakeRepository([_movie()]);
      final provider = _provider(repository, now: now);
      await provider.load();
      final stamp = DateTime.utc(2025, 12, 24, 18, 30);

      await provider.setStartedAt(provider.items.single, stamp);

      expect(repository.writes.single, <String, dynamic>{
        'started_at': isoDateTime(stamp),
      });
      expect(provider.items.single.startedAt, isNotNull);
    });

    test('deleteItem removes the item from the list', () async {
      final repository = _FakeRepository([_movie(), _movie(id: 'm2')]);
      final provider = _provider(repository);
      await provider.load();

      await provider.deleteItem(provider.items.first);

      expect(repository.deleted, ['m']);
      expect(provider.items.map((item) => item.id), ['m2']);
    });

    test('a failing write propagates and keeps the stored state', () async {
      final repository = _FakeRepository([_movie()], failTracking: true);
      final provider = _provider(repository);
      await provider.load();

      await expectLater(
        provider.setStatus(provider.items.single, MediaStatus.completed),
        throwsA(isA<MediaRepositoryException>()),
      );
      expect(provider.items.single.status, MediaStatus.planned);
    });

    test('itemById resolves the live copy', () async {
      final repository = _FakeRepository([_movie(id: 'm1'), _movie(id: 'm2')]);
      final provider = _provider(repository);
      await provider.load();

      expect(provider.itemById('m2')?.id, 'm2');
      expect(provider.itemById('missing'), isNull);
      expect(provider.itemById(null), isNull);
    });
  });
}
