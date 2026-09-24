import 'json_utils.dart';
import 'media_item.dart';

/// Builds TMDB image URLs from the `*_path` values the API returns.
///
/// Paths are relative (e.g. `/xlaY2zyz…jpg`); a `null` / empty path yields
/// `null` so callers can fall back to a placeholder instead of crashing.
class TmdbImages {
  const TmdbImages._();

  static const String _base = 'https://image.tmdb.org/t/p';

  /// Poster image, defaulting to the `w342` bucket used by list thumbnails.
  static String? poster(String? path, {String size = 'w342'}) =>
      _url(path, size);

  /// Backdrop / still image.
  static String? still(String? path, {String size = 'w300'}) =>
      _url(path, size);

  static String? _url(String? path, String size) {
    if (path == null || path.isEmpty) return null;
    return '$_base/$size$path';
  }
}

/// The TMDB media types the app tracks. Books come from a different source.
enum TmdbMediaType {
  movie('movie', 'Movie', MediaKind.movie),
  tv('tv', 'Series', MediaKind.series);

  const TmdbMediaType(this.wire, this.label, this.mediaKind);

  /// `movie` / `tv` as used by the API (`media_type`).
  final String wire;

  /// Human readable label for the UI.
  final String label;

  /// The corresponding [MediaKind] persisted in Supabase.
  final MediaKind mediaKind;

  static TmdbMediaType? tryFromWire(Object? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// Extracts the 4-digit year from a TMDB date string (`YYYY-MM-DD`).
///
/// TMDB is inconsistent: dates may be missing, empty or partial, so anything
/// that does not start with 4 digits yields `null`.
int? _yearFromDate(Object? value) {
  final text = jsonString(value);
  if (text == null || text.length < 4) return null;
  return int.tryParse(text.substring(0, 4));
}

/// A single hit from `search/movie`, `search/tv` or `search/multi`.
class TmdbSearchResult {
  const TmdbSearchResult({
    required this.id,
    required this.type,
    required this.title,
    this.originalTitle,
    this.year,
    this.posterPath,
    this.overview,
  });

  /// Parses a raw search result. Returns `null` for entries that are not
  /// movies or series (e.g. `media_type: person` in `search/multi`).
  static TmdbSearchResult? fromJson(Map<String, dynamic> json) {
    final id = jsonInt(json['id']);
    // `search/multi` returns `media_type`; the per-type endpoints do not, so
    // callers may pass [fallbackType].
    final type =
        TmdbMediaType.tryFromWire(json['media_type']) ??
        TmdbMediaType.tryFromWire(json['_fallbackType']);
    if (id == null || type == null) return null;

    final title = jsonString(
      json[type == TmdbMediaType.movie ? 'title' : 'name'],
    );
    if (title == null || title.isEmpty) return null;

    return TmdbSearchResult(
      id: id,
      type: type,
      title: title,
      originalTitle: jsonString(
        json[type == TmdbMediaType.movie ? 'original_title' : 'original_name'],
      ),
      year: _yearFromDate(
        json[type == TmdbMediaType.movie ? 'release_date' : 'first_air_date'],
      ),
      posterPath: jsonString(json['poster_path']),
      overview: jsonString(json['overview']),
    );
  }

  /// TMDB id.
  final int id;

  /// Movie or series.
  final TmdbMediaType type;

  final String title;
  final String? originalTitle;

  /// Release / first-air year.
  final int? year;
  final String? posterPath;
  final String? overview;

  /// Full poster URL (`w342`), or `null` when the API returned no artwork.
  String? get posterUrl => TmdbImages.poster(posterPath);

  /// A one-line teaser for list rows (first [maxLength] characters).
  String? get shortOverview {
    final text = overview?.trim();
    if (text == null || text.isEmpty) return null;
    if (text.length <= 140) return text;
    return '${text.substring(0, 137)}…';
  }
}

/// Fields shared by movie and TV detail responses.
abstract class TmdbDetails {
  const TmdbDetails();

  int get id;
  TmdbMediaType get type;
  String get title;
  String? get originalTitle;
  int? get year;
  String? get posterPath;
  String? get overview;

  String? get posterUrl => TmdbImages.poster(posterPath);

  /// Builds the [MediaItem] that "Add to library" persists.
  MediaItem toMediaItem();
}

/// `movie/{id}` response (only the fields the app needs).
class TmdbMovieDetails extends TmdbDetails {
  const TmdbMovieDetails({
    required this.id,
    required this.title,
    this.originalTitle,
    this.year,
    this.runtime,
    this.posterPath,
    this.overview,
  });

  factory TmdbMovieDetails.fromJson(Map<String, dynamic> json) {
    return TmdbMovieDetails(
      id: jsonInt(json['id']) ?? 0,
      title: jsonString(json['title']) ?? '',
      originalTitle: jsonString(json['original_title']),
      year: _yearFromDate(json['release_date']),
      runtime: jsonInt(json['runtime']),
      posterPath: jsonString(json['poster_path']),
      overview: jsonString(json['overview']),
    );
  }

  @override
  final int id;
  @override
  final String title;
  @override
  final String? originalTitle;
  @override
  final int? year;
  @override
  final String? posterPath;
  @override
  final String? overview;

  /// Runtime in minutes.
  final int? runtime;

  @override
  TmdbMediaType get type => TmdbMediaType.movie;

  @override
  MediaItem toMediaItem() => MediaItem(
    kind: MediaKind.movie,
    title: title,
    originalTitle: originalTitle,
    releaseYear: year,
    overview: overview,
    posterUrl: posterUrl,
    externalSource: 'tmdb',
    externalId: '$id',
  );
}

/// `tv/{id}` response (only the fields the app needs).
class TmdbTvDetails extends TmdbDetails {
  const TmdbTvDetails({
    required this.id,
    required this.name,
    this.originalName,
    this.year,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.episodeRunTime = const <int>[],
    this.seasons = const <TmdbSeasonSummary>[],
    this.posterPath,
    this.overview,
  });

  factory TmdbTvDetails.fromJson(Map<String, dynamic> json) {
    return TmdbTvDetails(
      id: jsonInt(json['id']) ?? 0,
      name: jsonString(json['name']) ?? '',
      originalName: jsonString(json['original_name']),
      year: _yearFromDate(json['first_air_date']),
      numberOfSeasons: jsonInt(json['number_of_seasons']),
      numberOfEpisodes: jsonInt(json['number_of_episodes']),
      episodeRunTime: _intList(json['episode_run_time']),
      seasons: _seasonSummaries(json['seasons']),
      posterPath: jsonString(json['poster_path']),
      overview: jsonString(json['overview']),
    );
  }

  @override
  final int id;
  final String name;
  final String? originalName;
  @override
  final int? year;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;

  /// Typical episode runtime(s) in minutes — often empty for new shows.
  final List<int> episodeRunTime;

  /// The season list as returned by `tv/{id}` — used by Phase 3b to know which
  /// seasons to fetch. **Includes** the specials (`season_number == 0`); the
  /// caller decides whether to skip them.
  final List<TmdbSeasonSummary> seasons;
  @override
  final String? posterPath;
  @override
  final String? overview;

  @override
  TmdbMediaType get type => TmdbMediaType.tv;

  @override
  String get title => name;

  @override
  String? get originalTitle => originalName;

  @override
  MediaItem toMediaItem() => MediaItem(
    kind: MediaKind.series,
    title: name,
    originalTitle: originalName,
    releaseYear: year,
    overview: overview,
    posterUrl: posterUrl,
    externalSource: 'tmdb',
    externalId: '$id',
    totalSeasons: numberOfSeasons,
    totalEpisodes: numberOfEpisodes,
  );
}

/// One entry of a `tv/{id}` `seasons` array.
class TmdbSeasonSummary {
  const TmdbSeasonSummary({
    required this.seasonNumber,
    this.name,
    this.episodeCount,
    this.posterPath,
  });

  factory TmdbSeasonSummary.fromJson(Map<String, dynamic> json) {
    return TmdbSeasonSummary(
      seasonNumber: jsonInt(json['season_number']) ?? 0,
      name: jsonString(json['name']),
      episodeCount: jsonInt(json['episode_count']),
      posterPath: jsonString(json['poster_path']),
    );
  }

  /// `0` is the specials season.
  final int seasonNumber;
  final String? name;

  /// Number of episodes TMDB reports for the season (may be `null`).
  final int? episodeCount;
  final String? posterPath;

  /// Whether this is the specials season (`season 0`).
  bool get isSpecials => seasonNumber == 0;
}

List<TmdbSeasonSummary> _seasonSummaries(Object? value) {
  if (value is! List) return const <TmdbSeasonSummary>[];
  return value
      .whereType<Map>()
      .map((e) => TmdbSeasonSummary.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

/// A single episode inside [TmdbSeasonDetails].
class TmdbEpisode {
  const TmdbEpisode({
    required this.episodeNumber,
    this.name,
    this.overview,
    this.airDate,
    this.runtime,
    this.stillPath,
  });

  factory TmdbEpisode.fromJson(Map<String, dynamic> json) {
    return TmdbEpisode(
      episodeNumber: jsonInt(json['episode_number']) ?? 0,
      name: jsonString(json['name']),
      overview: jsonString(json['overview']),
      airDate: jsonDateTime(json['air_date']),
      runtime: jsonInt(json['runtime']),
      stillPath: jsonString(json['still_path']),
    );
  }

  final int episodeNumber;
  final String? name;
  final String? overview;
  final DateTime? airDate;

  /// Runtime in minutes.
  final int? runtime;
  final String? stillPath;

  String? get stillUrl => TmdbImages.still(stillPath);
}

/// `tv/{id}/season/{n}` response — used by the Phase 4 episode browser.
class TmdbSeasonDetails {
  const TmdbSeasonDetails({
    required this.seasonNumber,
    this.name,
    this.overview,
    this.posterPath,
    this.episodes = const <TmdbEpisode>[],
  });

  factory TmdbSeasonDetails.fromJson(Map<String, dynamic> json) {
    final rawEpisodes = json['episodes'];
    return TmdbSeasonDetails(
      seasonNumber: jsonInt(json['season_number']) ?? 0,
      name: jsonString(json['name']),
      overview: jsonString(json['overview']),
      posterPath: jsonString(json['poster_path']),
      episodes: rawEpisodes is List
          ? rawEpisodes
                .whereType<Map>()
                .map((e) => TmdbEpisode.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const <TmdbEpisode>[],
    );
  }

  final int seasonNumber;
  final String? name;
  final String? overview;
  final String? posterPath;
  final List<TmdbEpisode> episodes;

  String? get posterUrl => TmdbImages.poster(posterPath);
}

List<int> _intList(Object? value) {
  if (value is! List) return const <int>[];
  return value.map(jsonInt).whereType<int>().toList();
}
