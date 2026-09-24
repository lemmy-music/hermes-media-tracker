import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';
import '../models/book_result.dart';
import '../models/json_utils.dart';
import 'isbn.dart';

/// An OpenLibrary failure translated into a message safe to show the user.
class OpenLibraryException implements Exception {
  const OpenLibraryException(this.message, {this.statusCode, this.cause});

  /// User-facing message, localized to the request language.
  final String message;

  /// HTTP status code, when the failure came from a response.
  final int? statusCode;

  /// The original error, kept for logging / debugging.
  final Object? cause;

  @override
  String toString() =>
      'OpenLibraryException: $message'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}'
      '${cause == null ? '' : ' — $cause'}';
}

/// Thin, typed wrapper around the OpenLibrary API.
///
/// OpenLibrary needs **no API key and no authentication** — the client is
/// therefore always usable, unlike [TmdbClient] which requires a build-time
/// token.
///
/// Every request has a 15s timeout and is translated into an
/// [OpenLibraryException] with a user-readable, localized message. Books are
/// *not* stored per edition: a search hit is a **work** (`/works/OL…W`), which
/// is what `external_id` stores and what [fetchDetails] loads.
class OpenLibraryClient {
  OpenLibraryClient({
    http.Client? httpClient,
    this.language = AppLanguage.fallback,
  }) : _http = httpClient ?? http.Client();

  static const String baseUrl = 'https://openlibrary.org';

  static const Duration _timeout = Duration(seconds: 15);

  /// Default number of search hits requested (matches the UI's list).
  static const int defaultLimit = 20;

  /// Keeps the response compact — OpenLibrary returns huge vanity fields
  /// otherwise. Exactly the columns the app parses.
  static const String searchFields =
      'key,title,author_name,first_publish_year,cover_i,edition_count,'
      'language,isbn,number_of_pages_median';

  final http.Client _http;

  /// Default language for localized error messages and (German) result
  /// ranking. Per-call overrides are available on [search] / [fetchDetails].
  final AppLanguage language;

  // ───────────────────────────────────────────────────────────────────────────
  // search
  // ───────────────────────────────────────────────────────────────────────────

  /// Searches works by title / author. Returns `[]` for an empty query
  /// without calling the API.
  ///
  /// [language] `de` does **not** filter — it only moves hits whose `language`
  /// array contains `ger`/`deu` to the front (stable partition), so works
  /// without language metadata never disappear.
  Future<List<BookResult>> search(
    String query, {
    int limit = defaultLimit,
    AppLanguage? language,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <BookResult>[];

    final json = await _get(
      '/search.json',
      query: <String, String>{
        'q': trimmed,
        'limit': '$limit',
        'fields': searchFields,
      },
      language: language,
    );

    final docs = json['docs'];
    if (docs is! List) return const <BookResult>[];

    final parsed = <BookResult>[];
    for (final entry in docs) {
      if (entry is! Map) continue;
      final result = BookResult.fromJson(Map<String, dynamic>.from(entry));
      if (result != null) parsed.add(result);
    }
    return rankForLanguage(parsed, language ?? this.language);
  }

  /// Stable partition: German hits first, everything else keeps its order.
  ///
  /// Deliberately *not* a filter — OpenLibrary's `language` array is often
  /// missing or describes only one edition, so hard-filtering would drop good
  /// matches (see the class doc).
  static List<BookResult> rankForLanguage(
    List<BookResult> results,
    AppLanguage language,
  ) {
    if (language != AppLanguage.de || results.isEmpty) return results;
    final german = <BookResult>[];
    final rest = <BookResult>[];
    for (final result in results) {
      (result.isGerman ? german : rest).add(result);
    }
    return <BookResult>[...german, ...rest];
  }

  // ───────────────────────────────────────────────────────────────────────────
  // details
  // ───────────────────────────────────────────────────────────────────────────

  /// `works/<key>.json` — `description` (string **or** object) plus a
  /// `first_sentence` fallback.
  ///
  /// [workKey] accepts `/works/OL27448W`, `/books/OL7353617M` (an edition, see
  /// [lookupByIsbn]) or a bare `OL27448W` / `OL7353617M`. The bare form is
  /// routed by its suffix: `…M` is an edition, everything else a work.
  Future<BookDetails> fetchDetails(String workKey, {AppLanguage? language}) {
    return _getBook('/${_bookPath(workKey)}.json', language: language);
  }

  /// `isbn/<isbn>.json` — an **edition**; kept as a low-level helper.
  ///
  /// The endpoint 302-redirects to `/books/OL…M.json` and the payload carries
  /// no author names, which is why the UI uses [lookupByIsbn] instead.
  Future<BookDetails> fetchByIsbn(String isbn, {AppLanguage? language}) {
    final clean = cleanIsbn(isbn);
    if (clean.isEmpty) {
      throw OpenLibraryException(
        AppStrings(language ?? this.language).openLibraryNotFound,
      );
    }
    return _getBook('/isbn/$clean.json', language: language);
  }

  /// Looks up a book by ISBN for the search UI (Phase 6a, text entry).
  ///
  /// **Edition vs. work:** `/isbn/<isbn>.json` resolves to an *edition*
  /// (`/books/OL…M`), not a work (`/works/OL…W`). The app stores books per
  /// **work** (see [BookDetails] / `BookResult.toMediaItem`), so we read the
  /// edition's linked work key (`works[0].key`) and return a work-level
  /// [BookResult] — exactly the shape a normal title search yields. The tile,
  /// the detail sheet and "Add to library" therefore work unchanged, and
  /// `external_id` stays a work key so an ISBN add also dedups against a later
  /// title search. Only when an edition has no linked work do we fall back to
  /// the edition key (still loadable via [fetchDetails]).
  ///
  /// The edition payload has no author names, so they are enriched with one
  /// best-effort `q=isbn:…` search call; a failure there is non-fatal (the
  /// result simply has no author line).
  ///
  /// Returns `null` when OpenLibrary has no book for this ISBN (HTTP 404 or an
  /// edition without a title). Network / timeout / server errors still throw an
  /// [OpenLibraryException] so the caller can distinguish "not found" from
  /// "could not ask".
  Future<BookResult?> lookupByIsbn(String isbn, {AppLanguage? language}) async {
    final clean = cleanIsbn(isbn);
    if (clean.isEmpty) return null;

    Map<String, dynamic> edition;
    try {
      edition = await _get('/isbn/$clean.json', language: language);
    } on OpenLibraryException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }

    final title = jsonString(edition['title'])?.trim();
    if (title == null || title.isEmpty) return null;

    // Reuse the tolerant edition parser for cover / pages / year / ISBNs.
    final parsed = BookDetails.fromJson(edition);

    final workKey = _firstRelationKey(edition['works']);
    final editionKey = jsonString(edition['key']);

    // Author names live on the work, not on the edition — enrich tolerantly.
    var authors = const <String>[];
    try {
      final hits = await search('isbn:$clean', limit: 1, language: language);
      if (hits.isNotEmpty) authors = hits.first.authors;
    } on OpenLibraryException {
      // Non-fatal: the edition alone is a usable result.
    }

    final isbns = <String>[
      clean,
      ...parsed.isbns.where((isbn) => isbn != clean),
    ];

    return BookResult(
      key: workKey != null
          ? '/works/$workKey'
          : (editionKey ?? '/books/$clean'),
      title: title,
      authors: authors,
      firstPublishYear: parsed.firstPublishYear,
      coverId: parsed.coverId,
      languages: _relationKeys(edition['languages']),
      isbns: isbns,
      pageCount: parsed.pageCount,
    );
  }

  /// Normalizes a work / edition key to a `works/…` or `books/…` path segment.
  static String _bookPath(String key) {
    final trimmed = key.trim().replaceAll(RegExp(r'^/+'), '');
    if (trimmed.startsWith('works/') || trimmed.startsWith('books/')) {
      return trimmed;
    }
    // Bare OpenLibrary ids: `OL…M` is an edition, `OL…W` (and anything else)
    // a work.
    if (RegExp(r'^OL\d+M$').hasMatch(trimmed)) return 'books/$trimmed';
    return 'works/$trimmed';
  }

  /// The bare key of the first `{key: /…}` entry of an OpenLibrary relation
  /// list (used for `works`, `languages`), or `null`.
  static String? _firstRelationKey(Object? value) {
    final keys = _relationKeys(value);
    return keys.isEmpty ? null : keys.first;
  }

  /// Bare keys (last path segment) of an OpenLibrary relation list such as
  /// `[{"key": "/languages/eng"}]` → `["eng"]`.
  static List<String> _relationKeys(Object? value) {
    if (value is! List) return const <String>[];
    final keys = <String>[];
    for (final entry in value) {
      Object? raw;
      if (entry is Map) raw = entry['key'];
      raw ??= entry;
      final text = jsonString(raw);
      if (text == null || text.isEmpty) continue;
      keys.add(text.split('/').last);
    }
    return keys;
  }

  Future<BookDetails> _getBook(String path, {AppLanguage? language}) async {
    final json = await _get(path, language: language);
    return BookDetails.fromJson(json);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // plumbing
  // ───────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
    AppLanguage? language,
  }) async {
    final strings = AppStrings(language ?? this.language);
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);

    http.Response response;
    try {
      response = await _http
          .get(
            uri,
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(_timeout);
    } on TimeoutException catch (error) {
      throw OpenLibraryException(strings.openLibraryTimeout, cause: error);
    } on http.ClientException catch (error) {
      throw OpenLibraryException(strings.openLibraryUnreachable, cause: error);
    } catch (error) {
      throw OpenLibraryException(strings.openLibraryUnreachable, cause: error);
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 404:
        throw OpenLibraryException(
          strings.openLibraryNotFound,
          statusCode: 404,
        );
      default:
        throw OpenLibraryException(
          strings.openLibraryRequestFailed,
          statusCode: response.statusCode,
        );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw OpenLibraryException(strings.openLibraryUnexpectedResponse);
    } on OpenLibraryException {
      rethrow;
    } on FormatException catch (error) {
      throw OpenLibraryException(
        strings.openLibraryUnreadableResponse,
        cause: error,
      );
    }
  }

  /// Closes the underlying HTTP client.
  void dispose() => _http.close();
}
