import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';
import '../models/book_result.dart';

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
  /// [workKey] accepts both `/works/OL27448W` and a bare `OL27448W`.
  Future<BookDetails> fetchDetails(String workKey, {AppLanguage? language}) {
    return _getBook('/${_workPath(workKey)}.json', language: language);
  }

  /// `isbn/<isbn>.json` — an **edition**; used by the Phase 6 barcode scanner.
  ///
  /// There is no UI yet, the method exists so the scanner can be wired up
  /// without touching this client.
  Future<BookDetails> fetchByIsbn(String isbn, {AppLanguage? language}) {
    final clean = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    if (clean.isEmpty) {
      throw OpenLibraryException(
        AppStrings(language ?? this.language).openLibraryNotFound,
      );
    }
    return _getBook('/isbn/$clean.json', language: language);
  }

  /// Normalizes a work key / id to a `works/…` path segment.
  static String _workPath(String workKey) {
    final trimmed = workKey.trim().replaceAll(RegExp(r'^/+'), '');
    if (trimmed.startsWith('works/')) return trimmed;
    return 'works/$trimmed';
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
