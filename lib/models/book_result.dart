import 'json_utils.dart';
import 'media_item.dart';

/// Builds cover image URLs for the OpenLibrary Covers API.
///
/// Covers are served by id (`cover_i` from a search hit) or by ISBN — both
/// without authentication. A missing / invalid value yields `null` so callers
/// fall back to the placeholder instead of crashing.
class OpenLibraryImages {
  const OpenLibraryImages._();

  static const String _base = 'https://covers.openlibrary.org/b';

  /// Small cover used by list thumbnails (~96px).
  static const String listSize = 'M';

  /// Large cover used by the detail sheet.
  static const String detailSize = 'L';

  /// `.../b/id/<coverId>-<size>.jpg`, or `null` when no cover id is known.
  static String? coverById(int? coverId, {String size = listSize}) {
    if (coverId == null || coverId <= 0) return null;
    return '$_base/id/$coverId-$size.jpg';
  }

  /// `.../b/isbn/<isbn>-<size>.jpg`, or `null` for a missing / empty ISBN.
  static String? coverByIsbn(String? isbn, {String size = listSize}) {
    final clean = _cleanIsbn(isbn);
    if (clean == null) return null;
    return '$_base/isbn/$clean-$size.jpg';
  }

  static String? _cleanIsbn(String? isbn) {
    if (isbn == null) return null;
    final clean = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    return clean.isEmpty ? null : clean;
  }
}

/// The ISO-639 codes OpenLibrary uses for German editions (`ger`, `deu`).
const Set<String> _kGermanLanguageCodes = <String>{'ger', 'deu'};

/// Whether [code] is one of the German language codes OpenLibrary returns.
bool isGermanLanguageCode(Object? code) =>
    code != null &&
    _kGermanLanguageCodes.contains(code.toString().toLowerCase());

/// Extracts a 4-digit year from a free-text date (`1954`, `July 29, 1954`).
int? yearFromText(Object? value) {
  final text = jsonString(value);
  if (text == null) return null;
  final match = RegExp(r'\b(\d{4})\b').firstMatch(text);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// Reads a field that may be a plain string **or** an OpenLibrary
/// `{"type": …, "value": …}` object — used for `description` and
/// `first_sentence`. Returns `null` for anything else (or an empty string).
String? textValue(Object? value) {
  String? candidate;
  if (value is String) {
    candidate = value;
  } else if (value is Map) {
    final inner = value['value'];
    if (inner is String) candidate = inner;
  }
  final text = candidate?.trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// A single hit from `search.json` — the book pendant to `TmdbSearchResult`.
class BookResult {
  const BookResult({
    required this.key,
    required this.title,
    this.authors = const <String>[],
    this.firstPublishYear,
    this.coverId,
    this.editionCount,
    this.languages = const <String>[],
    this.isbns = const <String>[],
    this.pageCount,
  });

  /// Parses a raw hit from `fields=…`. Returns `null` when the entry has no
  /// usable key / title, so a malformed row cannot crash the list.
  static BookResult? fromJson(Map<String, dynamic> json) {
    final key = jsonString(json['key']);
    final title = jsonString(json['title'])?.trim();
    if (key == null || key.isEmpty || title == null || title.isEmpty) {
      return null;
    }
    return BookResult(
      key: key,
      title: title,
      authors: jsonStringList(json['author_name']),
      firstPublishYear:
          jsonInt(json['first_publish_year']) ??
          yearFromText(json['first_publish_year']),
      coverId: jsonInt(json['cover_i']),
      editionCount: jsonInt(json['edition_count']),
      languages: jsonStringList(json['language']),
      isbns: jsonStringList(json['isbn']),
      pageCount: jsonInt(json['number_of_pages_median']),
    );
  }

  /// The work key as returned by the API, e.g. `/works/OL27448W`.
  final String key;

  final String title;
  final List<String> authors;
  final int? firstPublishYear;
  final int? coverId;

  /// How many editions OpenLibrary knows for this work.
  final int? editionCount;

  /// ISO-639 codes of the editions OpenLibrary indexed (`eng`, `ger`, …).
  final List<String> languages;

  final List<String> isbns;

  /// `number_of_pages_median` — `null` when OpenLibrary has no page data.
  final int? pageCount;

  /// The key without the `/works/` prefix, e.g. `OL27448W`.
  String get workId =>
      key.startsWith('/works/') ? key.substring('/works/'.length) : key;

  /// Cover URL for list thumbnails, or `null` when the hit has no cover.
  String? get coverUrl => OpenLibraryImages.coverById(coverId);

  /// Cover URL for the detail sheet.
  String? get coverLargeUrl =>
      OpenLibraryImages.coverById(coverId, size: OpenLibraryImages.detailSize);

  /// The first ISBN, used as the stored `isbn` column.
  String? get isbn => isbns.isEmpty ? null : isbns.first;

  /// `true` when OpenLibrary lists a German edition for this work.
  bool get isGerman => languages.any(isGermanLanguageCode);

  /// Builds the [MediaItem] that "Add to library" persists.
  ///
  /// [description] lets the caller fold in the (lazily loaded) work
  /// description; [totalPages], [isbn] and [coverUrl] let it prefer the richer
  /// detail values while falling back to the search snapshot.
  MediaItem toMediaItem({
    String? description,
    int? totalPages,
    String? isbn,
    String? coverUrl,
    int? releaseYear,
  }) => MediaItem(
    kind: MediaKind.book,
    title: title,
    authors: authors,
    releaseYear: releaseYear ?? firstPublishYear,
    overview: description,
    posterUrl: coverUrl ?? this.coverUrl,
    externalSource: 'openlibrary',
    externalId: key,
    totalPages: totalPages ?? pageCount,
    isbn: isbn ?? this.isbn,
  );
}

/// `works/<key>.json` (and, best effort, an `isbn/<isbn>.json` edition).
class BookDetails {
  const BookDetails({
    this.key,
    required this.title,
    this.description,
    this.firstPublishYear,
    this.coverId,
    this.pageCount,
    this.isbns = const <String>[],
    this.subjects = const <String>[],
  });

  /// Tolerant parser: `description` / `first_sentence` may be a string or an
  /// object (see [textValue]); a missing work key is tolerated so an edition
  /// response still parses.
  factory BookDetails.fromJson(Map<String, dynamic> json) {
    return BookDetails(
      key: jsonString(json['key']),
      title: jsonString(json['title'])?.trim() ?? '',
      description:
          textValue(json['description']) ?? textValue(json['first_sentence']),
      firstPublishYear:
          yearFromText(json['first_publish_date']) ??
          yearFromText(json['publish_date']),
      coverId: _firstCoverId(json['covers']) ?? jsonInt(json['cover_i']),
      pageCount:
          jsonInt(json['number_of_pages']) ??
          jsonInt(json['number_of_pages_median']),
      isbns: <String>[
        ...jsonStringList(json['isbn_13']),
        ...jsonStringList(json['isbn_10']),
        ...jsonStringList(json['isbn']),
      ],
      subjects: jsonStringList(json['subjects']),
    );
  }

  /// The work / edition key, e.g. `/works/OL27448W`.
  final String? key;

  final String title;

  /// Description (falling back to `first_sentence`), or `null`.
  final String? description;

  final int? firstPublishYear;
  final int? coverId;
  final int? pageCount;
  final List<String> isbns;
  final List<String> subjects;

  /// Cover URL for the detail sheet.
  String? get coverLargeUrl =>
      OpenLibraryImages.coverById(coverId, size: OpenLibraryImages.detailSize);

  /// The first ISBN of the edition, or `null`.
  String? get isbn => isbns.isEmpty ? null : isbns.first;

  /// Cover URL for list-sized usage (stored as `poster_url`).
  String? get coverUrl => OpenLibraryImages.coverById(coverId);
}

int? _firstCoverId(Object? covers) {
  if (covers is! List) return null;
  for (final cover in covers) {
    final id = jsonInt(cover);
    if (id != null && id > 0) return id;
  }
  return null;
}
