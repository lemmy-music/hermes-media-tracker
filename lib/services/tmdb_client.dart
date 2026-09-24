import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../l10n/app_strings.dart';
import '../models/tmdb_result.dart';

/// A TMDB failure translated into a message that is safe to show the user.
class TmdbException implements Exception {
  const TmdbException(
    this.message, {
    this.statusCode,
    this.missingToken = false,
    this.cause,
  });

  /// User-facing message, localized to the request language.
  final String message;

  /// HTTP status code, when the failure came from a response.
  final int? statusCode;

  /// `true` when the request was never sent because no token was configured.
  final bool missingToken;

  /// The original error, kept for logging / debugging.
  final Object? cause;

  @override
  String toString() =>
      'TmdbException: $message'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}'
      '${cause == null ? '' : ' — $cause'}';
}

/// The kind of search to run — one entry per (future) metadata source tab.
///
/// The UI renders the filter chips generically from these values. `books` is
/// **not** served by TMDB: the search screen routes it to the OpenLibrary
/// client, which is why [TmdbClient.search] never receives it.
enum TmdbSearchScope {
  all('All'),
  movie('Movies'),
  tv('Series'),
  books('Books');

  const TmdbSearchScope(this.label);

  /// Label for the filter chip.
  final String label;
}

/// Thin, typed wrapper around the TMDB v3 REST API.
///
/// Authentication uses the v4 **Read Access Token** via the
/// `Authorization: Bearer <token>` header (never an `api_key` query param).
/// Every request has a 15s timeout and is translated into a [TmdbException]
/// with a user-readable message.
class TmdbClient {
  TmdbClient({
    http.Client? httpClient,
    String? token,
    this.language = defaultLanguage,
  }) : _http = httpClient ?? http.Client(),
       _token = token ?? AppConfig.tmdbToken;

  static const String _base = AppConfig.tmdbApiBase;
  static const Duration _timeout = Duration(seconds: 15);

  /// TMDB `language` value used when a call does not override it.
  static const String defaultLanguage = 'en-US';

  final http.Client _http;
  final String _token;

  /// Default TMDB `language` for every request (`de-DE` / `en-US`).
  ///
  /// The app passes the active UI language per call (see [search] /
  /// [fetchDetails]'s `language` argument) so a language switch takes effect
  /// immediately without rebuilding the client.
  final String language;

  /// Whether a token is available. When `false` every call throws a
  /// [TmdbException] with `missingToken: true`.
  bool get hasToken => _token.isNotEmpty;

  // ───────────────────────────────────────────────────────────────────────────
  // search
  // ───────────────────────────────────────────────────────────────────────────

  /// Searches movies and/or series.
  ///
  /// [scope] `all` uses `search/multi` (filters out people), `movie` /
  /// `tv` use the dedicated endpoints for exact results.
  /// [page] is 1-based (TMDB's paging).
  /// [language] overrides [TmdbClient.language] for this request.
  Future<List<TmdbSearchResult>> search(
    String query, {
    TmdbSearchScope scope = TmdbSearchScope.all,
    int page = 1,
    String? language,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <TmdbSearchResult>[];

    // Books come from OpenLibrary — the screen never calls TMDB for them.
    // Guarding here keeps the client total (and the switch below exhaustive).
    if (scope == TmdbSearchScope.books) return const <TmdbSearchResult>[];

    final path = switch (scope) {
      TmdbSearchScope.all || TmdbSearchScope.books => '/search/multi',
      TmdbSearchScope.movie => '/search/movie',
      TmdbSearchScope.tv => '/search/tv',
    };

    // The per-type endpoints omit `media_type`; supply it as a fallback so
    // a single parser handles all three responses.
    final fallback = switch (scope) {
      TmdbSearchScope.movie => 'movie',
      TmdbSearchScope.tv => 'tv',
      TmdbSearchScope.all || TmdbSearchScope.books => null,
    };

    final json = await _get(
      path,
      query: {'query': trimmed, 'page': '$page', 'include_adult': 'false'},
      language: language,
    );

    final results = json['results'];
    if (results is! List) return const <TmdbSearchResult>[];

    final parsed = <TmdbSearchResult>[];
    for (final entry in results) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      if (fallback != null) map['_fallbackType'] = fallback;
      final result = TmdbSearchResult.fromJson(map);
      if (result != null) parsed.add(result);
    }
    return parsed;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // details
  // ───────────────────────────────────────────────────────────────────────────

  /// `movie/{id}` — runtime included.
  Future<TmdbMovieDetails> fetchMovie(int id, {String? language}) async {
    final json = await _get('/movie/$id', language: language);
    return TmdbMovieDetails.fromJson(json);
  }

  /// `tv/{id}` — season / episode counts included.
  Future<TmdbTvDetails> fetchTv(int id, {String? language}) async {
    final json = await _get('/tv/$id', language: language);
    return TmdbTvDetails.fromJson(json);
  }

  /// `tv/{id}/season/{n}` — the episode list (used by Phase 4).
  Future<TmdbSeasonDetails> fetchSeason(
    int tvId,
    int seasonNumber, {
    String? language,
  }) async {
    final json = await _get(
      '/tv/$tvId/season/$seasonNumber',
      language: language,
    );
    return TmdbSeasonDetails.fromJson(json);
  }

  /// Loads the right detail response for a search hit.
  Future<TmdbDetails> fetchDetails(
    TmdbSearchResult result, {
    String? language,
  }) {
    return switch (result.type) {
      TmdbMediaType.movie => fetchMovie(result.id, language: language),
      TmdbMediaType.tv => fetchTv(result.id, language: language),
    };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // plumbing
  // ───────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
    String? language,
  }) async {
    final requestLanguage = language ?? this.language;
    final strings = AppStrings.forTmdb(requestLanguage);

    if (!hasToken) {
      throw TmdbException(strings.tmdbNotConfigured, missingToken: true);
    }

    final uri = Uri.parse('$_base$path').replace(
      queryParameters: <String, String>{'language': requestLanguage, ...?query},
    );

    http.Response response;
    try {
      response = await _http
          .get(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $_token',
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on TimeoutException catch (error) {
      throw TmdbException(strings.tmdbTimeout, cause: error);
    } on http.ClientException catch (error) {
      throw TmdbException(strings.tmdbUnreachable, cause: error);
    } catch (error) {
      throw TmdbException(strings.tmdbUnreachable, cause: error);
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 401:
        throw TmdbException(strings.tmdbInvalidToken, statusCode: 401);
      case 404:
        throw TmdbException(strings.tmdbNotFound, statusCode: 404);
      case 429:
        throw TmdbException(strings.tmdbRateLimited, statusCode: 429);
      default:
        throw TmdbException(
          strings.tmdbRequestFailed,
          statusCode: response.statusCode,
        );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw TmdbException(strings.tmdbUnexpectedResponse);
    } on TmdbException {
      rethrow;
    } on FormatException catch (error) {
      throw TmdbException(strings.tmdbUnreadableResponse, cause: error);
    }
  }

  /// Closes the underlying HTTP client.
  void dispose() => _http.close();
}
