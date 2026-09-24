/// Pure, testable search / filter / sort rules behind the library screen.
///
/// Deliberately free of Flutter / Supabase imports — the whole feature is
/// *what subset of the already-loaded list should the user see, in which
/// order*. Everything here is a pure function of its inputs, which keeps the
/// widget dumb and the behaviour unit-testable.
///
/// The screen holds its search text, filters and sort order as **session-only
/// state** (see `LibraryScreen`); the provider's list is never modified — these
/// functions take a copy and return a new list.
library;

import '../models/media_item.dart';

/// Media-type filter of the library (`all` = no restriction).
enum LibraryKindFilter {
  all(null),
  movies(MediaKind.movie),
  series(MediaKind.series),
  books(MediaKind.book);

  const LibraryKindFilter(this.kind);

  /// The kind this option keeps; `null` for [LibraryKindFilter.all].
  final MediaKind? kind;

  /// `true` when [item] passes this filter.
  bool allows(MediaItem item) => kind == null || item.kind == kind;
}

/// Tracking-status filter of the library (`all` = no restriction).
enum LibraryStatusFilter {
  all(null),
  planned(MediaStatus.planned),
  inProgress(MediaStatus.inProgress),
  completed(MediaStatus.completed),
  dropped(MediaStatus.dropped);

  const LibraryStatusFilter(this.status);

  /// The status this option keeps; `null` for [LibraryStatusFilter.all].
  final MediaStatus? status;

  /// `true` when [item] passes this filter.
  bool allows(MediaItem item) => status == null || item.status == status;
}

/// Sort order of the library list.
enum LibrarySort {
  /// Newest first, by `created_at` descending.
  recentlyAdded,

  /// Title A–Z (see [normalizeSearchText] for the case/diacritic handling).
  titleAZ,

  /// Release year descending.
  releaseYear,

  /// Progress descending (missing progress counts as `0`).
  progress;

  /// The default order the library screen opens with.
  static const LibrarySort defaultValue = LibrarySort.recentlyAdded;
}

// ─────────────────────────────────────────────────────────────────────────────
// text normalisation
// ─────────────────────────────────────────────────────────────────────────────

/// Folds one lowercase character to its unaccented form (multi-char results
/// are possible, e.g. `ß` → `ss`).
String _foldChar(String char) {
  switch (char) {
    case 'ä':
    case 'á':
    case 'à':
    case 'â':
    case 'ã':
    case 'å':
      return 'a';
    case 'ç':
      return 'c';
    case 'é':
    case 'è':
    case 'ê':
    case 'ë':
      return 'e';
    case 'ï':
    case 'í':
    case 'ì':
    case 'î':
      return 'i';
    case 'ñ':
      return 'n';
    case 'ö':
    case 'ó':
    case 'ò':
    case 'ô':
    case 'õ':
      return 'o';
    case 'œ':
      return 'oe';
    case 'æ':
      return 'ae';
    case 'ß':
      return 'ss';
    case 'ü':
    case 'ú':
    case 'ù':
    case 'û':
      return 'u';
    case 'ý':
    case 'ÿ':
      return 'y';
    default:
      return char;
  }
}

/// Lowercases [value] and folds common Latin diacritics (umlauts, accents,
/// `ß`) to their ASCII base form.
///
/// Both the query and the searched fields go through this, so the match is
/// case-insensitive **and** diacritic-tolerant: searching `"herr"` finds
/// `"Der Herr der Ringe"`, `"muller"` finds `"Müller"` and `"strasse"` finds
/// `"Straße"` — and vice versa.
String normalizeSearchText(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    buffer.write(_foldChar(String.fromCharCode(rune)));
  }
  return buffer.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// search
// ─────────────────────────────────────────────────────────────────────────────

/// `true` when [item] matches [query].
///
/// Always searches the **title**; books additionally match on their
/// **authors**. An empty / whitespace-only query matches everything. Missing
/// fields never throw — an item without an author simply has nothing to match.
bool matchesSearch(MediaItem item, String query) {
  final needle = normalizeSearchText(query.trim());
  if (needle.isEmpty) return true;

  if (normalizeSearchText(item.title).contains(needle)) return true;

  if (item.kind == MediaKind.book) {
    for (final author in item.authors) {
      if (normalizeSearchText(author).contains(needle)) return true;
    }
  }
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// filtering
// ─────────────────────────────────────────────────────────────────────────────

/// The items of [items] that pass the search text and both filters.
///
/// The three conditions are combined with a logical **AND** (search *and* kind
/// *and* status), and the original order is preserved.
List<MediaItem> filterLibrary({
  required List<MediaItem> items,
  String query = '',
  LibraryKindFilter kind = LibraryKindFilter.all,
  LibraryStatusFilter status = LibraryStatusFilter.all,
}) {
  return <MediaItem>[
    for (final item in items)
      if (kind.allows(item) &&
          status.allows(item) &&
          matchesSearch(item, query))
        item,
  ];
}

/// `true` when the given search text / filters actually restrict the list.
///
/// The sort order is **not** a filter, so it does not count here.
bool hasLibraryFilter({
  required String query,
  required LibraryKindFilter kind,
  required LibraryStatusFilter status,
}) {
  return query.trim().isNotEmpty ||
      kind != LibraryKindFilter.all ||
      status != LibraryStatusFilter.all;
}

// ─────────────────────────────────────────────────────────────────────────────
// sorting
// ─────────────────────────────────────────────────────────────────────────────

int _compareDateDesc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // Missing dates sort to the end.
  if (b == null) return -1;
  return b.compareTo(a);
}

int _compareIntDescNullLast(int? a, int? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // Missing years sort to the end.
  if (b == null) return -1;
  return b.compareTo(a);
}

int _compareNumDesc(num a, num b) => b.compareTo(a);

/// Compares two items for [sort]; `0` means "keep the current order".
int _compareBy(MediaItem a, MediaItem b, LibrarySort sort) => switch (sort) {
  LibrarySort.recentlyAdded => _compareDateDesc(a.createdAt, b.createdAt),
  LibrarySort.titleAZ => normalizeSearchText(
    a.title,
  ).compareTo(normalizeSearchText(b.title)),
  LibrarySort.releaseYear => _compareIntDescNullLast(
    a.releaseYear,
    b.releaseYear,
  ),
  LibrarySort.progress => _compareNumDesc(
    a.progressPercent ?? 0,
    b.progressPercent ?? 0,
  ),
};

/// Returns a **new** list with [items] sorted by [sort].
///
/// Item order is **stable**: equal keys (same title, same year, two items with
/// no progress, …) keep their relative order from [items], so the list does not
/// shuffle between rebuilds.
List<MediaItem> sortLibrary(List<MediaItem> items, LibrarySort sort) {
  final order = List<int>.generate(items.length, (index) => index);
  order.sort((a, b) {
    final result = _compareBy(items[a], items[b], sort);
    return result != 0 ? result : a.compareTo(b);
  });
  return <MediaItem>[for (final index in order) items[index]];
}

/// The single entry point of the library view: filter, then sort.
List<MediaItem> applyLibraryView({
  required List<MediaItem> items,
  String query = '',
  LibraryKindFilter kind = LibraryKindFilter.all,
  LibraryStatusFilter status = LibraryStatusFilter.all,
  LibrarySort sort = LibrarySort.defaultValue,
}) {
  return sortLibrary(
    filterLibrary(items: items, query: query, kind: kind, status: status),
    sort,
  );
}
