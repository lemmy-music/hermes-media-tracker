import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/models/tmdb_result.dart';
import 'package:media_tracker/services/tmdb_client.dart';

/// Builds a client backed by [handler] and a fixed token.
TmdbClient _client(
  Future<http.Response> Function(http.Request) handler, {
  String token = 'test-token',
}) => TmdbClient(httpClient: MockClient(handler), token: token);

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

const Map<String, dynamic> _movieHit = {
  'id': 27205,
  'media_type': 'movie',
  'title': 'Inception',
  'original_title': 'Inception',
  'release_date': '2010-07-15',
  'poster_path': '/poster.jpg',
  'overview': 'A thief who steals corporate secrets.',
};

const Map<String, dynamic> _tvHit = {
  'id': 95396,
  'media_type': 'tv',
  'name': 'Severance',
  'original_name': 'Severance',
  'first_air_date': '2022-02-17',
  'poster_path': '/tv.jpg',
  'overview': 'Work-life balance taken literally.',
};

void main() {
  group('TmdbClient.search', () {
    test('search/multi keeps movies and series, drops people', () async {
      late Uri requestUri;
      late String authHeader;
      final client = _client((request) async {
        requestUri = request.url;
        authHeader = request.headers['authorization'] ?? '';
        return _json({
          'results': [
            _movieHit,
            _tvHit,
            {'id': 42, 'media_type': 'person', 'name': 'Someone'},
          ],
        });
      });

      final results = await client.search('inception');

      expect(requestUri.path, '/3/search/multi');
      expect(requestUri.queryParameters['query'], 'inception');
      expect(requestUri.queryParameters['language'], 'en-US');
      expect(authHeader, 'Bearer test-token');

      expect(results, hasLength(2));
      expect(results[0].type, TmdbMediaType.movie);
      expect(results[0].title, 'Inception');
      expect(results[0].year, 2010);
      expect(
        results[0].posterUrl,
        'https://image.tmdb.org/t/p/w342/poster.jpg',
      );
      expect(results[1].type, TmdbMediaType.tv);
      expect(results[1].title, 'Severance');
      expect(results[1].year, 2022);
    });

    test('search/movie uses the typed endpoint and infers the kind', () async {
      late Uri requestUri;
      final client = _client((request) async {
        requestUri = request.url;
        // The typed endpoint omits `media_type`.
        final hit = Map<String, dynamic>.from(_movieHit)..remove('media_type');
        return _json({
          'results': [hit],
        });
      });

      final results = await client.search(
        'inception',
        scope: TmdbSearchScope.movie,
      );

      expect(requestUri.path, '/3/search/movie');
      expect(results, hasLength(1));
      expect(results.single.type, TmdbMediaType.movie);
    });

    test('returns an empty list when there are no results', () async {
      final client = _client((_) async => _json({'results': <dynamic>[]}));
      expect(await client.search('zzzz'), isEmpty);
    });

    test('does not call the API for an empty query', () async {
      final client = _client(
        (_) async => throw StateError('should not be called'),
      );
      expect(await client.search('   '), isEmpty);
    });

    test('a per-request language overrides the client default', () async {
      late Uri requestUri;
      final client = _client((request) async {
        requestUri = request.url;
        return _json({'results': <dynamic>[]});
      });

      await client.search('herr der ringe', language: 'de-DE');
      expect(requestUri.queryParameters['language'], 'de-DE');
    });

    test('the constructor language is the default for every request',
        () async {
      late Uri requestUri;
      final client = TmdbClient(
        httpClient: MockClient((request) async {
          requestUri = request.url;
          return _json({'id': 1, 'title': 'X'});
        }),
        token: 'test-token',
        language: 'de-DE',
      );

      await client.fetchMovie(1);
      expect(requestUri.queryParameters['language'], 'de-DE');
    });
  });

  group('TmdbClient localization', () {
    test('localizes error messages to the request language', () async {
      final client = _client((_) async => _json({}, status: 429));

      await expectLater(
        client.search('inception', language: 'de-DE'),
        throwsA(
          isA<TmdbException>().having(
            (e) => e.message,
            'message',
            contains('Zu viele Anfragen'),
          ),
        ),
      );
    });

    test('localizes the missing-token message', () async {
      final client = _client(
        (_) async => throw StateError('should not be called'),
        token: '',
      );

      await expectLater(
        client.search('inception', language: 'de-DE'),
        throwsA(
          isA<TmdbException>().having(
            (e) => e.message,
            'message',
            contains('nicht konfiguriert'),
          ),
        ),
      );
    });
  });

  group('TmdbClient error handling', () {
    test('throws a missing-token error without calling the API', () async {
      final client = _client(
        (_) async => throw StateError('should not be called'),
        token: '',
      );

      await expectLater(
        client.search('inception'),
        throwsA(
          isA<TmdbException>().having(
            (e) => e.missingToken,
            'missingToken',
            isTrue,
          ),
        ),
      );
    });

    test('maps 401 to a token error', () async {
      final client = _client(
        (_) async => _json({'status_message': 'nope'}, status: 401),
      );

      await expectLater(
        client.search('inception'),
        throwsA(
          isA<TmdbException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('token')),
        ),
      );
    });

    test('maps 429 to a rate-limit error', () async {
      final client = _client((_) async => _json({}, status: 429));

      await expectLater(
        client.search('inception'),
        throwsA(
          isA<TmdbException>().having(
            (e) => e.message,
            'message',
            contains('Too many requests'),
          ),
        ),
      );
    });

    test('maps network failures to a readable message', () async {
      final client = _client((_) async => throw http.ClientException('boom'));

      await expectLater(
        client.search('inception'),
        throwsA(
          isA<TmdbException>().having(
            (e) => e.message,
            'message',
            contains('reach TMDB'),
          ),
        ),
      );
    });

    test('rejects an unreadable body', () async {
      final client = _client((_) async => http.Response('not json', 200));

      await expectLater(
        client.search('inception'),
        throwsA(isA<TmdbException>()),
      );
    });
  });

  group('TmdbClient details', () {
    test('fetchMovie parses runtime', () async {
      final client = _client((request) async {
        expect(request.url.path, '/3/movie/27205');
        return _json({
          'id': 27205,
          'title': 'Inception',
          'original_title': 'Inception',
          'release_date': '2010-07-15',
          'runtime': 148,
          'poster_path': '/p.jpg',
          'overview': 'A thief.',
        });
      });

      final details = await client.fetchMovie(27205);
      expect(details.runtime, 148);
      expect(details.year, 2010);
      expect(details.toMediaItem().kind, MediaKind.movie);
    });

    test('fetchTv parses season / episode counts', () async {
      final client = _client((request) async {
        expect(request.url.path, '/3/tv/95396');
        return _json({
          'id': 95396,
          'name': 'Severance',
          'original_name': 'Severance',
          'first_air_date': '2022-02-17',
          'number_of_seasons': 3,
          'number_of_episodes': 19,
          'episode_run_time': <dynamic>[],
          'poster_path': '/s.jpg',
        });
      });

      final details = await client.fetchTv(95396);
      expect(details.numberOfSeasons, 3);
      expect(details.numberOfEpisodes, 19);

      final item = details.toMediaItem();
      expect(item.kind, MediaKind.series);
      expect(item.totalSeasons, 3);
      expect(item.totalEpisodes, 19);
      expect(item.externalSource, 'tmdb');
      expect(item.externalId, '95396');
    });

    test('fetchSeason parses the episode list', () async {
      final client = _client((request) async {
        expect(request.url.path, '/3/tv/95396/season/1');
        return _json({
          'season_number': 1,
          'name': 'Season 1',
          'episodes': [
            {
              'episode_number': 1,
              'name': 'Good News About Hell',
              'overview': 'Mark is promoted.',
              'air_date': '2022-02-17',
              'runtime': 59,
              'still_path': '/still.jpg',
            },
          ],
        });
      });

      final season = await client.fetchSeason(95396, 1);
      expect(season.seasonNumber, 1);
      expect(season.episodes, hasLength(1));
      expect(season.episodes.single.name, 'Good News About Hell');
      expect(season.episodes.single.runtime, 59);
      expect(
        season.episodes.single.stillUrl,
        'https://image.tmdb.org/t/p/w300/still.jpg',
      );
    });

    test('hasToken reflects the configured token', () {
      expect(_client((_) async => _json({})).hasToken, isTrue);
      expect(_client((_) async => _json({}), token: '').hasToken, isFalse);
    });
  });

  group('TmdbSearchResult model', () {
    test('parses a hit and builds the full poster URL', () {
      final result = TmdbSearchResult.fromJson(
        Map<String, dynamic>.from(_tvHit),
      )!;
      expect(result.id, 95396);
      expect(result.type, TmdbMediaType.tv);
      expect(result.originalTitle, 'Severance');
      expect(result.year, 2022);
    });

    test('_yearFromDate tolerates missing / partial dates', () {
      final noDate = TmdbSearchResult.fromJson({
        'id': 1,
        'media_type': 'movie',
        'title': 'X',
      })!;
      expect(noDate.year, isNull);
      expect(noDate.posterUrl, isNull);
    });

    test('shortOverview truncates long text', () {
      final result = TmdbSearchResult.fromJson({
        'id': 1,
        'media_type': 'movie',
        'title': 'X',
        'overview': 'a' * 500,
      })!;
      expect(result.shortOverview, isNotNull);
      expect(result.shortOverview!.length, lessThanOrEqualTo(140));
      expect(result.shortOverview, endsWith('…'));
    });

    test('rejects entries without a title', () {
      expect(
        TmdbSearchResult.fromJson({'id': 1, 'media_type': 'movie'}),
        isNull,
      );
    });
  });

  group('TmdbImages', () {
    test('returns null for missing paths and a URL otherwise', () {
      expect(TmdbImages.poster(null), isNull);
      expect(TmdbImages.poster(''), isNull);
      expect(
        TmdbImages.poster('/a.jpg'),
        'https://image.tmdb.org/t/p/w342/a.jpg',
      );
      expect(
        TmdbImages.poster('/a.jpg', size: 'w500'),
        'https://image.tmdb.org/t/p/w500/a.jpg',
      );
    });
  });
}
