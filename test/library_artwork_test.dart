import 'package:flutter_test/flutter_test.dart';

import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/services/library_filter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// builders
// ─────────────────────────────────────────────────────────────────────────────

MediaItem _item({
  required MediaKind kind,
  required String title,
  String? posterUrl,
  DateTime? createdAt,
}) => MediaItem(
  id: '$kind-$title',
  kind: kind,
  title: title,
  posterUrl: posterUrl,
  createdAt: createdAt,
);

void main() {
  group('selectCategoryArtwork', () {
    test('picks the newest cover of the category by created_at desc', () {
      final items = <MediaItem>[
        _item(
          kind: MediaKind.movie,
          title: 'Old',
          posterUrl: 'old.jpg',
          createdAt: DateTime(2024),
        ),
        _item(
          kind: MediaKind.movie,
          title: 'New',
          posterUrl: 'new.jpg',
          createdAt: DateTime(2026),
        ),
        _item(
          kind: MediaKind.movie,
          title: 'Mid',
          posterUrl: 'mid.jpg',
          createdAt: DateTime(2025),
        ),
      ];

      final artwork = selectCategoryArtwork(
        items,
        filter: LibraryKindFilter.movies,
      );

      expect(artwork.hasCover, isTrue);
      expect(artwork.heroUrl, 'new.jpg');
      // The next-newest covers fan behind the hero, newest first.
      expect(artwork.layerUrls, ['mid.jpg', 'old.jpg']);
    });

    test('skips entries without a cover when choosing the hero', () {
      final items = <MediaItem>[
        // Newest entry, but no artwork → must not become the hero.
        _item(
          kind: MediaKind.book,
          title: 'NoCover',
          createdAt: DateTime(2026),
        ),
        _item(
          kind: MediaKind.book,
          title: 'Covered',
          posterUrl: 'cover.jpg',
          createdAt: DateTime(2025),
        ),
      ];

      final artwork = selectCategoryArtwork(
        items,
        filter: LibraryKindFilter.books,
      );

      expect(artwork.heroUrl, 'cover.jpg');
    });

    test('returns no cover for an empty category', () {
      final items = <MediaItem>[
        _item(kind: MediaKind.movie, title: 'M', posterUrl: 'm.jpg'),
      ];

      final artwork = selectCategoryArtwork(
        items,
        filter: LibraryKindFilter.books,
      );

      expect(artwork.hasCover, isFalse);
      expect(artwork.heroUrl, isNull);
      expect(artwork.layerUrls, isEmpty);
    });

    test('returns no cover when every entry lacks artwork', () {
      final items = <MediaItem>[
        _item(kind: MediaKind.book, title: 'A'),
        _item(kind: MediaKind.book, title: 'B'),
      ];

      final artwork = selectCategoryArtwork(
        items,
        filter: LibraryKindFilter.books,
      );

      expect(artwork, same(CategoryArtwork.none));
      expect(artwork.hasCover, isFalse);
    });

    test('"all" spans every media kind and takes the newest overall', () {
      final items = <MediaItem>[
        _item(
          kind: MediaKind.movie,
          title: 'M',
          posterUrl: 'm.jpg',
          createdAt: DateTime(2024),
        ),
        _item(
          kind: MediaKind.series,
          title: 'S',
          posterUrl: 's.jpg',
          createdAt: DateTime(2025),
        ),
        _item(
          kind: MediaKind.book,
          title: 'B',
          posterUrl: 'b.jpg',
          createdAt: DateTime(2026),
        ),
      ];

      final artwork = selectCategoryArtwork(
        items,
        filter: LibraryKindFilter.all,
      );

      expect(artwork.heroUrl, 'b.jpg');
      expect(artwork.layerUrls, ['s.jpg', 'm.jpg']);
    });

    test('provides the requested number of fan layers', () {
      final items = <MediaItem>[
        for (var i = 0; i < 5; i++)
          _item(
            kind: MediaKind.movie,
            title: 'M$i',
            posterUrl: 'm$i.jpg',
            createdAt: DateTime(2026, 1, i + 1),
          ),
      ];

      final artwork = selectCategoryArtwork(
        items,
        filter: LibraryKindFilter.movies,
        fanLayers: 2,
      );

      expect(artwork.heroUrl, 'm4.jpg');
      expect(artwork.layerUrls.length, 2);
      expect(artwork.layerUrls, ['m3.jpg', 'm2.jpg']);
    });

    test('reuses the newest cover when only one exists', () {
      final items = <MediaItem>[
        _item(
          kind: MediaKind.movie,
          title: 'Only',
          posterUrl: 'only.jpg',
          createdAt: DateTime(2026),
        ),
      ];

      final artwork = selectCategoryArtwork(
        items,
        filter: LibraryKindFilter.movies,
      );

      expect(artwork.heroUrl, 'only.jpg');
      expect(artwork.layerUrls, ['only.jpg', 'only.jpg']);
    });

    test('keeps list order on equal / missing created_at (stable)', () {
      final items = <MediaItem>[
        _item(kind: MediaKind.movie, title: 'First', posterUrl: 'first.jpg'),
        _item(kind: MediaKind.movie, title: 'Second', posterUrl: 'second.jpg'),
      ];

      final artwork = selectCategoryArtwork(
        items,
        filter: LibraryKindFilter.movies,
      );

      expect(artwork.heroUrl, 'first.jpg');
      expect(artwork.layerUrls.first, 'second.jpg');
    });
  });
}
