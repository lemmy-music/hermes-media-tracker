import 'package:flutter_test/flutter_test.dart';

import 'package:media_tracker/models/episode.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _bookRow() => <String, dynamic>{
      'id': '11111111-1111-1111-1111-111111111111',
      'user_id': '22222222-2222-2222-2222-222222222222',
      'kind': 'book',
      'title': 'Dune',
      'original_title': 'Dune',
      'release_year': 1965,
      'overview': 'Spice must flow.',
      'poster_url': null,
      'external_source': 'openlibrary',
      'external_id': 'OL123W',
      'authors': <dynamic>['Frank Herbert'],
      'total_pages': 412,
      'isbn': '9780441013593',
      'total_seasons': null,
      'total_episodes': null,
      'status': 'in_progress',
      // `numeric` may arrive as a string depending on the column type.
      'progress_percent': '42.50',
      'progress_current': 175,
      'started_at': '2026-01-02T03:04:05.000Z',
      'completed_at': null,
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-03T10:00:00.000Z',
    };

Map<String, dynamic> _episodeRow() => <String, dynamic>{
      'id': '33333333-3333-3333-3333-333333333333',
      'user_id': '22222222-2222-2222-2222-222222222222',
      'media_item_id': '11111111-1111-1111-1111-111111111111',
      'season_number': 2,
      'episode_number': 5,
      'name': 'Breakage',
      'overview': null,
      'air_date': '2026-02-03',
      'still_url': null,
      'runtime': 47,
      'watched': true,
      'watched_at': '2026-02-04T20:15:00.000Z',
      'created_at': '2026-02-01T00:00:00.000Z',
    };

void main() {
  group('MediaItem', () {
    test('fromMap maps every column', () {
      final item = MediaItem.fromMap(_bookRow());

      expect(item.id, '11111111-1111-1111-1111-111111111111');
      expect(item.kind, MediaKind.book);
      expect(item.title, 'Dune');
      expect(item.originalTitle, 'Dune');
      expect(item.releaseYear, 1965);
      expect(item.overview, 'Spice must flow.');
      expect(item.posterUrl, isNull);
      expect(item.hasPoster, isFalse);
      expect(item.externalSource, 'openlibrary');
      expect(item.externalId, 'OL123W');
      expect(item.authors, ['Frank Herbert']);
      expect(item.totalPages, 412);
      expect(item.isbn, '9780441013593');
      expect(item.totalSeasons, isNull);
      expect(item.totalEpisodes, isNull);
      expect(item.status, MediaStatus.inProgress);
      expect(item.progressPercent, 42.5);
      expect(item.progressCurrent, 175);
      expect(item.startedAt, isNotNull);
      expect(item.completedAt, isNull);
      expect(item.createdAt, isNotNull);
      expect(item.updatedAt, isNotNull);
    });

    test('toMap uses snake_case and omits null values', () {
      final item = MediaItem.fromMap(_bookRow());
      final map = item.toMap();

      expect(map['kind'], 'book');
      expect(map['status'], 'in_progress');
      expect(map['progress_percent'], 42.5);
      expect(map['authors'], ['Frank Herbert']);
      expect(map.containsKey('completed_at'), isFalse);
      expect(map.containsKey('poster_url'), isFalse);
      // Server-managed columns are only present when known.
      expect(map.containsKey('created_at'), isTrue);
    });

    test('round-trips through toMap/fromMap', () {
      final original = MediaItem.fromMap(_bookRow());
      final roundTripped = MediaItem.fromMap(original.toMap());

      expect(roundTripped.id, original.id);
      expect(roundTripped.kind, original.kind);
      expect(roundTripped.title, original.title);
      expect(roundTripped.authors, original.authors);
      expect(roundTripped.status, original.status);
      expect(roundTripped.progressPercent, original.progressPercent);
      expect(roundTripped.startedAt, original.startedAt);
    });

    test('new items default to status planned', () {
      const item = MediaItem(kind: MediaKind.series, title: 'Severance');
      expect(item.status, MediaStatus.planned);
      expect(item.toMap()['status'], 'planned');
      expect(item.toMap().containsKey('id'), isFalse);
    });

    test('copyWith only overrides the given fields', () {
      final item = MediaItem.fromMap(_bookRow());
      final updated = item.copyWith(status: MediaStatus.completed);

      expect(updated.status, MediaStatus.completed);
      expect(updated.title, item.title);
      expect(updated.authors, item.authors);
    });

    test('unknown enum values are rejected', () {
      expect(() => MediaKind.fromWire('podcast'), throwsFormatException);
      expect(() => MediaStatus.fromWire('nope'), throwsFormatException);
    });
  });

  group('Episode', () {
    test('fromMap maps every column', () {
      final episode = Episode.fromMap(_episodeRow());

      expect(episode.id, '33333333-3333-3333-3333-333333333333');
      expect(episode.mediaItemId, '11111111-1111-1111-1111-111111111111');
      expect(episode.seasonNumber, 2);
      expect(episode.episodeNumber, 5);
      expect(episode.name, 'Breakage');
      expect(episode.overview, isNull);
      expect(episode.airDate, isNotNull);
      expect(episode.airDate!.year, 2026);
      expect(episode.runtime, 47);
      expect(episode.watched, isTrue);
      expect(episode.watchedAt, isNotNull);
    });

    test('toMap keeps the date-only column as YYYY-MM-DD', () {
      final map = Episode.fromMap(_episodeRow()).toMap();

      expect(map['media_item_id'], '11111111-1111-1111-1111-111111111111');
      expect(map['season_number'], 2);
      expect(map['episode_number'], 5);
      expect(map['air_date'], '2026-02-03');
      expect(map['watched'], isTrue);
      expect(map.containsKey('overview'), isFalse);
    });
  });

  group('error helpers', () {
    test('describePostgrestError explains a missing schema', () {
      final message = describePostgrestError(
        const PostgrestException(
          message: "Could not find the table 'public.media_items'",
          code: 'PGRST205',
        ),
        fallback: 'Could not load your library.',
      );

      expect(message, contains('schema'));
      expect(message, contains('0001_init.sql'));
    });

    test('describePostgrestError falls back to the generic message', () {
      final message = describePostgrestError(
        const PostgrestException(message: 'boom', code: 'XX000'),
        fallback: 'Could not load your library.',
      );

      expect(message, contains('Could not load your library.'));
      expect(message, contains('boom'));
    });
  });
}
