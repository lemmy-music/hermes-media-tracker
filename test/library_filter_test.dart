import 'package:flutter_test/flutter_test.dart';

import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/services/library_filter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// builders
// ─────────────────────────────────────────────────────────────────────────────

MediaItem _movie({
  String title = 'A Movie',
  String? id,
  MediaStatus status = MediaStatus.planned,
  int? releaseYear,
  double? progress,
  DateTime? createdAt,
}) => MediaItem(
  id: id,
  kind: MediaKind.movie,
  title: title,
  status: status,
  releaseYear: releaseYear,
  progressPercent: progress,
  createdAt: createdAt,
);

MediaItem _book({
  String title = 'A Book',
  String? id,
  List<String> authors = const <String>[],
  MediaStatus status = MediaStatus.planned,
  int? releaseYear,
  double? progress,
  DateTime? createdAt,
}) => MediaItem(
  id: id,
  kind: MediaKind.book,
  title: title,
  authors: authors,
  status: status,
  releaseYear: releaseYear,
  progressPercent: progress,
  createdAt: createdAt,
);

MediaItem _series({
  String title = 'A Series',
  String? id,
  MediaStatus status = MediaStatus.planned,
  int? releaseYear,
  double? progress,
  DateTime? createdAt,
}) => MediaItem(
  id: id,
  kind: MediaKind.series,
  title: title,
  status: status,
  releaseYear: releaseYear,
  progressPercent: progress,
  createdAt: createdAt,
);

List<String> _titles(List<MediaItem> items) => <String>[
  for (final item in items) item.title,
];

void main() {
  group('normalizeSearchText', () {
    test('lowercases and folds umlauts / accents', () {
      expect(normalizeSearchText('LOWERCASE'), 'lowercase');
      expect(normalizeSearchText('Über'), 'uber');
      expect(normalizeSearchText('Größe'), 'grosse');
      expect(normalizeSearchText('Café'), 'cafe');
      expect(normalizeSearchText('Straße'), 'strasse');
      expect(normalizeSearchText('Beyoncé'), 'beyonce');
      expect(normalizeSearchText('Ångström'), 'angstrom');
      expect(normalizeSearchText('ñandú'), 'nandu');
    });

    test('leaves plain text alone', () {
      expect(normalizeSearchText('der herr der ringe'), 'der herr der ringe');
    });
  });

  group('matchesSearch', () {
    test('an empty or whitespace-only query matches everything', () {
      final item = _movie(title: 'Inception');
      expect(matchesSearch(item, ''), isTrue);
      expect(matchesSearch(item, '   '), isTrue);
    });

    test('matches the title case-insensitively', () {
      final item = _movie(title: 'Der Herr der Ringe');
      expect(matchesSearch(item, 'herr'), isTrue);
      expect(matchesSearch(item, 'HERR'), isTrue);
      expect(matchesSearch(item, 'Ringe'), isTrue);
      expect(matchesSearch(item, 'Matrix'), isFalse);
    });

    test('tolerates umlauts and diacritics on both sides', () {
      final item = _movie(title: 'Über die Liebe');
      expect(matchesSearch(item, 'uber'), isTrue);
      expect(matchesSearch(item, 'Über'), isTrue);
      expect(matchesSearch(item, 'liebe'), isTrue);

      final umlaut = _book(title: 'Müller');
      expect(matchesSearch(umlaut, 'muller'), isTrue);
      expect(matchesSearch(umlaut, 'Müller'), isTrue);
    });

    test('books additionally match their authors', () {
      final book = _book(title: 'Dune', authors: const ['Frank Herbert']);
      expect(matchesSearch(book, 'herbert'), isTrue);
      expect(matchesSearch(book, 'frank'), isTrue);
      expect(matchesSearch(book, 'dune'), isTrue);
      expect(matchesSearch(book, 'asimov'), isFalse);
    });

    test('authors are only consulted for books', () {
      final movie = _movie(title: 'Dune');
      // A non-book item that happens to carry an author-like field must not
      // match on it — only its title is searched.
      final withAuthors = MediaItem(
        kind: MediaKind.movie,
        title: 'Dune',
        authors: const <String>['Frank Herbert'],
      );
      expect(matchesSearch(movie, 'herbert'), isFalse);
      expect(matchesSearch(withAuthors, 'herbert'), isFalse);
    });

    test('never crashes on missing fields', () {
      final untitled = _movie(title: '');
      expect(matchesSearch(untitled, ''), isTrue);
      expect(matchesSearch(untitled, 'x'), isFalse);

      final authorless = _book(title: 'Dune');
      expect(matchesSearch(authorless, 'herbert'), isFalse);
    });
  });

  group('filterLibrary', () {
    final items = <MediaItem>[
      _movie(title: 'Inception'),
      _series(title: 'Lost'),
      _book(title: 'Dune', authors: const ['Frank Herbert']),
    ];

    test('returns everything for the default filters', () {
      expect(_titles(filterLibrary(items: items)), _titles(items));
    });

    test('filters by media type', () {
      expect(
        _titles(filterLibrary(items: items, kind: LibraryKindFilter.books)),
        ['Dune'],
      );
      expect(
        _titles(filterLibrary(items: items, kind: LibraryKindFilter.movies)),
        ['Inception'],
      );
      expect(
        _titles(filterLibrary(items: items, kind: LibraryKindFilter.series)),
        ['Lost'],
      );
    });

    test('filters by status', () {
      final list = <MediaItem>[
        _movie(title: 'A', status: MediaStatus.planned),
        _movie(title: 'B', status: MediaStatus.inProgress),
        _movie(title: 'C', status: MediaStatus.completed),
        _movie(title: 'D', status: MediaStatus.dropped),
      ];
      expect(
        _titles(
          filterLibrary(items: list, status: LibraryStatusFilter.completed),
        ),
        ['C'],
      );
      expect(
        _titles(
          filterLibrary(items: list, status: LibraryStatusFilter.dropped),
        ),
        ['D'],
      );
      expect(
        _titles(
          filterLibrary(items: list, status: LibraryStatusFilter.inProgress),
        ),
        ['B'],
      );
    });

    test('combines search, type and status with AND', () {
      final list = <MediaItem>[
        _book(title: 'Dune', authors: const ['Frank Herbert']),
        _book(
          title: 'Dune Messiah',
          authors: const ['Frank Herbert'],
          status: MediaStatus.completed,
        ),
        _movie(title: 'Dune', status: MediaStatus.completed),
      ];
      final result = filterLibrary(
        items: list,
        query: 'herbert',
        kind: LibraryKindFilter.books,
        status: LibraryStatusFilter.completed,
      );
      expect(_titles(result), ['Dune Messiah']);
    });

    test('preserves the input order', () {
      final list = <MediaItem>[
        _movie(title: 'C'),
        _movie(title: 'A'),
        _movie(title: 'B'),
      ];
      expect(_titles(filterLibrary(items: list)), ['C', 'A', 'B']);
    });

    test('an empty input list stays empty', () {
      expect(
        filterLibrary(
          items: const <MediaItem>[],
          query: 'anything',
          kind: LibraryKindFilter.books,
        ),
        isEmpty,
      );
    });
  });

  group('hasLibraryFilter', () {
    test('is false for pristine state', () {
      expect(
        hasLibraryFilter(
          query: '',
          kind: LibraryKindFilter.all,
          status: LibraryStatusFilter.all,
        ),
        isFalse,
      );
      expect(
        hasLibraryFilter(
          query: '   ',
          kind: LibraryKindFilter.all,
          status: LibraryStatusFilter.all,
        ),
        isFalse,
      );
    });

    test('is true as soon as a query or a filter is set', () {
      expect(
        hasLibraryFilter(
          query: 'dune',
          kind: LibraryKindFilter.all,
          status: LibraryStatusFilter.all,
        ),
        isTrue,
      );
      expect(
        hasLibraryFilter(
          query: '',
          kind: LibraryKindFilter.books,
          status: LibraryStatusFilter.all,
        ),
        isTrue,
      );
      expect(
        hasLibraryFilter(
          query: '',
          kind: LibraryKindFilter.all,
          status: LibraryStatusFilter.completed,
        ),
        isTrue,
      );
    });
  });

  group('sortLibrary', () {
    test('recently added: newest first, missing dates last', () {
      final list = <MediaItem>[
        _movie(title: 'old', createdAt: DateTime(2024, 1, 1)),
        _movie(title: 'undated'),
        _movie(title: 'new', createdAt: DateTime(2026, 1, 1)),
      ];
      expect(_titles(sortLibrary(list, LibrarySort.recentlyAdded)), [
        'new',
        'old',
        'undated',
      ]);
    });

    test('recently added is stable for equal dates', () {
      final list = <MediaItem>[
        _movie(title: 'first', createdAt: DateTime(2026, 1, 1)),
        _movie(title: 'second', createdAt: DateTime(2026, 1, 1)),
      ];
      expect(_titles(sortLibrary(list, LibrarySort.recentlyAdded)), [
        'first',
        'second',
      ]);
    });

    test('title A–Z is case-insensitive and keeps leading articles', () {
      final list = <MediaItem>[
        _movie(title: 'the Matrix'),
        _movie(title: 'Arrival'),
        _movie(title: 'Der Herr der Ringe'),
        _movie(title: 'blade runner'),
      ];
      expect(_titles(sortLibrary(list, LibrarySort.titleAZ)), [
        'Arrival',
        'blade runner',
        'Der Herr der Ringe',
        'the Matrix',
      ]);
    });

    test('title A–Z is stable for equal titles', () {
      final list = <MediaItem>[
        _movie(title: 'Dune', id: 'a'),
        _movie(title: 'Dune', id: 'b'),
      ];
      final sorted = sortLibrary(list, LibrarySort.titleAZ);
      expect(<String?>[for (final i in sorted) i.id], ['a', 'b']);
    });

    test('release year: descending, missing years last', () {
      final list = <MediaItem>[
        _movie(title: '2010', releaseYear: 2010),
        _movie(title: 'unknown'),
        _movie(title: '2024', releaseYear: 2024),
        _movie(title: '2001', releaseYear: 2001),
      ];
      expect(_titles(sortLibrary(list, LibrarySort.releaseYear)), [
        '2024',
        '2010',
        '2001',
        'unknown',
      ]);
    });

    test('release year is stable for equal years', () {
      final list = <MediaItem>[
        _movie(title: 'first', releaseYear: 2000),
        _movie(title: 'second', releaseYear: 2000),
      ];
      expect(_titles(sortLibrary(list, LibrarySort.releaseYear)), [
        'first',
        'second',
      ]);
    });

    test('progress: descending, missing progress counts as 0', () {
      final list = <MediaItem>[
        _movie(title: '40', progress: 40),
        _movie(title: '0', progress: 0),
        _movie(title: '90', progress: 90),
        _movie(title: 'none'),
      ];
      expect(_titles(sortLibrary(list, LibrarySort.progress)), [
        '90',
        '40',
        '0',
        'none',
      ]);
    });

    test('progress is stable for equal values', () {
      final list = <MediaItem>[
        _movie(title: 'first', progress: 50),
        _movie(title: 'second', progress: 50),
      ];
      expect(_titles(sortLibrary(list, LibrarySort.progress)), [
        'first',
        'second',
      ]);
    });

    test('sorting an empty list is safe', () {
      for (final sort in LibrarySort.values) {
        expect(sortLibrary(const <MediaItem>[], sort), isEmpty);
      }
    });
  });

  group('applyLibraryView', () {
    test('filters and sorts in one call', () {
      final list = <MediaItem>[
        _book(
          title: 'Zulu',
          authors: const ['Herbert'],
          status: MediaStatus.completed,
        ),
        _book(
          title: 'Alpha',
          authors: const ['Herbert'],
          status: MediaStatus.completed,
        ),
        _book(title: 'Ignored', authors: const ['Other']),
      ];
      final result = applyLibraryView(
        items: list,
        query: 'herbert',
        kind: LibraryKindFilter.books,
        status: LibraryStatusFilter.completed,
        sort: LibrarySort.titleAZ,
      );
      expect(_titles(result), ['Alpha', 'Zulu']);
    });

    test('defaults to the recent-first order with no filtering', () {
      final list = <MediaItem>[
        _movie(title: 'old', createdAt: DateTime(2024, 1, 1)),
        _movie(title: 'new', createdAt: DateTime(2026, 1, 1)),
      ];
      expect(_titles(applyLibraryView(items: list)), ['new', 'old']);
    });
  });
}
