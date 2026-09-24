import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/tmdb_result.dart';

/// A TMDB failure translated into a message that is safe to show the user.
class TmdbException implements Exception {
  const TmdbException(
    this.message, {
    this.statusCode,
    this.missingToken = false,
    this.cause,
  });

  /// User-facing, English message.
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
/// Adding `books` later only requires a new enum value plus a branch in
/// [TmdbClient.search]; the UI already renders the filter generically.
enum TmdbSearchScope {
  all('All'),
  movie('Movies'),
  tv('Series');

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
  TmdbClient({http.Client? httpClient, String? token})
    : _http = httpClient ?? http.Client(),
      _token = token ?? AppConfig.tmdbToken;

  static const String _base = AppConfig.tmdbApiBase;
  static const Duration _timeout = Duration(seconds: 15);
  static const String _language = 'en-US';

  final http.Client _http;
  final String _token;

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
  Future<List<TmdbSearchResult>> search(
    String query, {
    TmdbSearchScope scope = TmdbSearchScope.all,
    int page = 1,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <TmdbSearchResult>[];

    final path = switch (scope) {
      TmdbSearchScope.all => '/search/multi',
      TmdbSearchScope.movie => '/search/movie',
      TmdbSearchScope.tv => '/search/tv',
    };

    // The per-type endpoints omit `media_type`; supply it as a fallback so
    // a single parser handles all three responses.
    final fallback = switch (scope) {
      TmdbSearchScope.movie => 'movie',
      TmdbSearchScope.tv => 'tv',
      TmdbSearchScope.all => null,
    };

    final json = await _get(
      path,
      query: {'query': trimmed, 'page': '$page', 'include_adult': 'false'},
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
  Future<TmdbMovieDetails> fetchMovie(int id) async {
    final json = await _get('/movie/$id');
    return TmdbMovieDetails.fromJson(json);
  }

  /// `tv/{id}` — season / episode counts included.
  Future<TmdbTvDetails> fetchTv(int id) async {
    final json = await _get('/tv/$id');
    return TmdbTvDetails.fromJson(json);
  }

  /// `tv/{id}/season/{n}` — the episode list (used by Phase 4).
  Future<TmdbSeasonDetails> fetchSeason(int tvId, int seasonNumber) async {
    final json = await _get('/tv/$tvId/season/$seasonNumber');
    return TmdbSeasonDetails.fromJson(json);
  }

  /// Loads the right detail response for a search hit.
  Future<TmdbDetails> fetchDetails(TmdbSearchResult result) {
    return switch (result.type) {
      TmdbMediaType.movie => fetchMovie(result.id),
      TmdbMediaType.tv => fetchTv(result.id),
    };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // plumbing
  // ───────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    if (!hasToken) {
      throw const TmdbException(
        'TMDB is not configured for this build. '
        'Rebuild with --dart-define=TMDB_TOKEN=….',
        missingToken: true,
      );
    }

    final uri = Uri.parse('$_base$path').replace(
      queryParameters: <String, String>{'language': _language, ...?query},
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
      throw TmdbException(
        'The request to TMDB timed out. Please try again.',
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw TmdbException(
        'Could not reach TMDB. Check your connection and try again.',
        cause: error,
      );
    } catch (error) {
      throw TmdbException(
        'Could not reach TMDB. Check your connection and try again.',
        cause: error,
      );
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 401:
        throw const TmdbException(
          'TMDB rejected the API token. Check that TMDB_TOKEN is valid.',
          statusCode: 401,
        );
      case 404:
        throw const TmdbException(
          'TMDB could not find that title.',
          statusCode: 404,
        );
      case 429:
        throw const TmdbException(
          'Too many requests to TMDB. Please wait a moment and retry.',
          statusCode: 429,
        );
      default:
        throw TmdbException(
          'TMDB request failed. Please try again.',
          statusCode: response.statusCode,
        );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const TmdbException('TMDB returned an unexpected response.');
    } on TmdbException {
      rethrow;
    } on FormatException catch (error) {
      throw TmdbException(
        'TMDB returned an unreadable response.',
        cause: error,
      );
    }
  }

  /// Closes the underlying HTTP client.
  void dispose() => _http.close();
}
