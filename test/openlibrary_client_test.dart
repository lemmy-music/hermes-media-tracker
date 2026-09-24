import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/models/book_result.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/services/openlibrary_client.dart';

/// Builds a client backed by [handler] — no network in tests.
OpenLibraryClient _client(
  Future<http.Response> Function(http.Request) handler, {
  AppLanguage language = AppLanguage.en,
}) => OpenLibraryClient(httpClient: MockClient(handler), language: language);

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

const Map<String, dynamic> _lotrHit = {
  'key': '/works/OL27448W',
  'title': 'The Lord of the Rings',
  'author_name': ['J.R.R. Tolkien'],
  'first_publish_year': 1954,
  'cover_i': 8231856,
  'edition_count': 42,
  'language': ['eng'],
  'isbn': ['9780618640157', '0618640150'],
  'number_of_pages_median': 1216,
};

const Map<String, dynamic> _germanHit = {
  'key': '/works/OL99999W',
  'title': 'Der Herr der Ringe',
  'author_name': ['J.R.R. Tolkien'],
  'first_publish_year': 1969,
  'language': ['ger', 'eng'],
};

void main() {
  group('OpenLibraryClient.search', () {
    test(
      'requests /search.json with the compact fields and parses hits',
      () async {
        late Uri requestUri;
        final client = _client((request) async {
          requestUri = request.url;
          return _json({
            'docs': [_lotrHit],
          });
        });

        final results = await client.search('herr der ringe');

        expect(requestUri.path, '/search.json');
        expect(requestUri.queryParameters['q'], 'herr der ringe');
        expect(requestUri.queryParameters['limit'], '20');
        expect(
          requestUri.queryParameters['fields'],
          OpenLibraryClient.searchFields,
        );

        expect(results, hasLength(1));
        final hit = results.single;
        expect(hit.key, '/works/OL27448W');
        expect(hit.workId, 'OL27448W');
        expect(hit.title, 'The Lord of the Rings');
        expect(hit.authors, ['J.R.R. Tolkien']);
        expect(hit.firstPublishYear, 1954);
        expect(hit.editionCount, 42);
        expect(hit.pageCount, 1216);
        expect(hit.isbn, '9780618640157');
        expect(
          hit.coverUrl,
          'https://covers.openlibrary.org/b/id/8231856-M.jpg',
        );
        expect(
          hit.coverLargeUrl,
          'https://covers.openlibrary.org/b/id/8231856-L.jpg',
        );
      },
    );

    test('URL-encodes the query', () async {
      late Uri requestUri;
      final client = _client((request) async {
        requestUri = request.url;
        return _json({'docs': <dynamic>[]});
      });

      await client.search('herr der ringe & mehr');
      expect(requestUri.queryParameters['q'], 'herr der ringe & mehr');
    });

    test('tolerates missing fields (no cover, no year, no authors)', () async {
      final client = _client(
        (_) async => _json({
          'docs': [
            {'key': '/works/OL1W', 'title': 'Minimal'},
          ],
        }),
      );

      final hit = (await client.search('minimal')).single;
      expect(hit.title, 'Minimal');
      expect(hit.authors, isEmpty);
      expect(hit.firstPublishYear, isNull);
      expect(hit.coverUrl, isNull);
      expect(hit.pageCount, isNull);
      expect(hit.isbn, isNull);
      expect(hit.isGerman, isFalse);
    });

    test('skips entries without a key or title', () async {
      final client = _client(
        (_) async => _json({
          'docs': [
            {'title': 'No key'},
            {'key': '/works/OL2W'},
            'not-a-map',
            _germanHit,
          ],
        }),
      );

      final results = await client.search('x');
      expect(results, hasLength(1));
      expect(results.single.key, '/works/OL99999W');
    });

    test('returns an empty list when the response has no docs', () async {
      final client = _client((_) async => _json({'numFound': 0}));
      expect(await client.search('zzzz'), isEmpty);
    });

    test('does not call the API for an empty query', () async {
      final client = _client(
        (_) async => throw StateError('should not be called'),
      );
      expect(await client.search('   '), isEmpty);
    });

    test('ranks German hits first on a German UI (stable partition)', () async {
      final english = <Map<String, dynamic>>[
        _lotrHit,
        {
          'key': '/works/OL3W',
          'title': 'Second English',
          'language': ['eng'],
        },
        _germanHit,
        {'key': '/works/OL4W', 'title': 'No language metadata'},
        {
          'key': '/works/OL5W',
          'title': 'Zweites Deutsch',
          'language': ['deu'],
        },
      ];
      final client = _client(
        (_) async => _json({'docs': english}),
        language: AppLanguage.de,
      );

      final results = await client.search('herr');
      expect(results.map((r) => r.title), [
        'Der Herr der Ringe',
        'Zweites Deutsch',
        'The Lord of the Rings',
        'Second English',
        'No language metadata',
      ]);
    });

    test('keeps the API order on an English UI', () async {
      final client = _client(
        (_) async => _json({
          'docs': [_lotrHit, _germanHit],
        }),
        language: AppLanguage.en,
      );

      final results = await client.search('herr');
      expect(results.map((r) => r.title), [
        'The Lord of the Rings',
        'Der Herr der Ringe',
      ]);
    });
  });

  group('OpenLibraryClient.fetchDetails', () {
    test('loads works/<key>.json and accepts a bare work id', () async {
      late Uri requestUri;
      final client = _client((request) async {
        requestUri = request.url;
        return _json({
          'key': '/works/OL27448W',
          'title': 'The Lord of the Rings',
          'description': 'A quest to destroy a ring.',
          'first_publish_date': 'July 29, 1954',
          'covers': [8231856],
        });
      });

      final details = await client.fetchDetails('OL27448W');
      expect(requestUri.path, '/works/OL27448W.json');
      expect(details.title, 'The Lord of the Rings');
      expect(details.description, 'A quest to destroy a ring.');
      expect(details.firstPublishYear, 1954);
      expect(
        details.coverLargeUrl,
        'https://covers.openlibrary.org/b/id/8231856-L.jpg',
      );
    });

    test('accepts the full /works/… key without doubling the prefix', () async {
      late Uri requestUri;
      final client = _client((request) async {
        requestUri = request.url;
        return _json({'key': '/works/OL27448W', 'title': 'X'});
      });

      await client.fetchDetails('/works/OL27448W');
      expect(requestUri.path, '/works/OL27448W.json');
    });

    test('parses `description` given as an object', () async {
      final client = _client(
        (_) async => _json({
          'title': 'X',
          'description': {
            'type': '/type/text',
            'value': 'Beschreibung aus einem Objekt.',
          },
        }),
      );

      final details = await client.fetchDetails('OL1W');
      expect(details.description, 'Beschreibung aus einem Objekt.');
    });

    test('falls back to first_sentence (string)', () async {
      final client = _client(
        (_) async => _json({
          'title': 'X',
          'first_sentence': 'It was a dark and stormy night.',
        }),
      );

      expect(
        (await client.fetchDetails('OL1W')).description,
        'It was a dark and stormy night.',
      );
    });

    test('falls back to first_sentence (object)', () async {
      final client = _client(
        (_) async => _json({
          'title': 'X',
          'first_sentence': {
            'type': '/type/text',
            'value': 'Ein dunkler und stürmischer Abend.',
          },
        }),
      );

      expect(
        (await client.fetchDetails('OL1W')).description,
        'Ein dunkler und stürmischer Abend.',
      );
    });

    test('tolerates a missing description entirely', () async {
      final client = _client((_) async => _json({'title': 'X'}));
      expect((await client.fetchDetails('OL1W')).description, isNull);
    });
  });

  group('OpenLibraryClient.fetchByIsbn', () {
    test('loads isbn/<isbn>.json and parses the edition', () async {
      late Uri requestUri;
      final client = _client((request) async {
        requestUri = request.url;
        return _json({
          'key': '/books/OL7353617M',
          'title': 'The Hobbit',
          'covers': [12345],
          'number_of_pages': 310,
          'publish_date': '1937',
          'isbn_13': ['9780261102217'],
        });
      });

      final details = await client.fetchByIsbn('978-0-261-10221-7');
      expect(requestUri.path, '/isbn/9780261102217.json');
      expect(details.title, 'The Hobbit');
      expect(details.pageCount, 310);
      expect(details.firstPublishYear, 1937);
      expect(details.isbn, '9780261102217');
    });

    test('rejects an empty ISBN without calling the API', () async {
      final client = _client(
        (_) async => throw StateError('should not be called'),
      );
      // The check runs before any request is scheduled.
      expect(
        () => client.fetchByIsbn('---'),
        throwsA(isA<OpenLibraryException>()),
      );
    });
  });

  group('OpenLibraryClient error handling', () {
    test('maps an HTTP error and keeps the status code', () async {
      final client = _client((_) async => _json({}, status: 500));

      await expectLater(
        client.search('x'),
        throwsA(
          isA<OpenLibraryException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.message, 'message', contains('failed')),
        ),
      );
    });

    test('maps 404 to a not-found message', () async {
      final client = _client((_) async => _json({}, status: 404));

      await expectLater(
        client.fetchDetails('OL0W'),
        throwsA(
          isA<OpenLibraryException>().having(
            (e) => e.message,
            'message',
            contains('could not find'),
          ),
        ),
      );
    });

    test('maps a timeout to a readable message', () async {
      final client = _client((_) async => throw TimeoutException('too slow'));

      await expectLater(
        client.search('x'),
        throwsA(
          isA<OpenLibraryException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    test('maps a network failure to a readable message', () async {
      final client = _client((_) async => throw http.ClientException('boom'));

      await expectLater(
        client.search('x'),
        throwsA(
          isA<OpenLibraryException>().having(
            (e) => e.message,
            'message',
            contains('reach OpenLibrary'),
          ),
        ),
      );
    });

    test('rejects an empty / unreadable body', () async {
      final client = _client((_) async => http.Response('', 200));

      await expectLater(
        client.search('x'),
        throwsA(
          isA<OpenLibraryException>().having(
            (e) => e.message,
            'message',
            contains('unreadable'),
          ),
        ),
      );
    });

    test('localizes error messages to the client language', () async {
      final client = _client(
        (_) async => _json({}, status: 500),
        language: AppLanguage.de,
      );

      await expectLater(
        client.search('x'),
        throwsA(
          isA<OpenLibraryException>().having(
            (e) => e.message,
            'message',
            contains('fehlgeschlagen'),
          ),
        ),
      );
    });
  });

  group('BookResult.toMediaItem', () {
    test('maps a hit onto the book columns', () async {
      final client = _client(
        (_) async => _json({
          'docs': [_lotrHit],
        }),
      );
      final hit = (await client.search('lotr')).single;

      final item = hit.toMediaItem(description: 'A quest.');
      expect(item.kind, MediaKind.book);
      expect(item.title, 'The Lord of the Rings');
      expect(item.authors, ['J.R.R. Tolkien']);
      expect(item.releaseYear, 1954);
      expect(item.overview, 'A quest.');
      expect(item.externalSource, 'openlibrary');
      expect(item.externalId, '/works/OL27448W');
      expect(item.totalPages, 1216);
      expect(item.isbn, '9780618640157');
      expect(item.posterUrl, contains('/id/8231856-M.jpg'));
      expect(item.status, MediaStatus.planned);

      // The Postgres payload keeps authors as a list (text[]).
      final body = item.toMap();
      expect(body['authors'], isA<List<String>>());
      expect(body['kind'], 'book');
      expect(body['external_source'], 'openlibrary');
    });

    test('detail values win over the search snapshot', () async {
      final client = _client(
        (_) async => _json({
          'docs': [
            {
              'key': '/works/OL7W',
              'title': 'Bare',
              'number_of_pages_median': 100,
            },
          ],
        }),
      );
      final hit = (await client.search('bare')).single;

      final item = hit.toMediaItem(
        totalPages: 300,
        isbn: '111',
        coverUrl: 'https://example.invalid/c.jpg',
      );
      expect(item.totalPages, 300);
      expect(item.isbn, '111');
      expect(item.posterUrl, 'https://example.invalid/c.jpg');
    });
  });

  group('OpenLibraryImages', () {
    test('builds cover URLs and yields null for missing values', () {
      expect(OpenLibraryImages.coverById(null), isNull);
      expect(OpenLibraryImages.coverById(0), isNull);
      expect(
        OpenLibraryImages.coverById(1),
        'https://covers.openlibrary.org/b/id/1-M.jpg',
      );
      expect(
        OpenLibraryImages.coverById(1, size: 'L'),
        'https://covers.openlibrary.org/b/id/1-L.jpg',
      );
      expect(OpenLibraryImages.coverByIsbn(null), isNull);
      expect(
        OpenLibraryImages.coverByIsbn('978-0-261-10221-7'),
        'https://covers.openlibrary.org/b/isbn/9780261102217-M.jpg',
      );
    });
  });
}
