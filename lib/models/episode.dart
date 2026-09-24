import 'json_utils.dart';

/// A row of `public.episodes` — cached episode metadata plus watch state.
///
/// `user_id` is deliberately **not** part of the model: ownership is injected
/// by [MediaRepository] on write and enforced by RLS on read.
class Episode {
  const Episode({
    this.id,
    required this.mediaItemId,
    required this.seasonNumber,
    required this.episodeNumber,
    this.name,
    this.overview,
    this.airDate,
    this.stillUrl,
    this.runtime,
    this.watched = false,
    this.watchedAt,
    this.createdAt,
  });

  /// Builds an episode from a PostgREST row.
  factory Episode.fromMap(Map<String, dynamic> map) {
    return Episode(
      id: jsonString(map['id']),
      mediaItemId: jsonString(map['media_item_id']) ?? '',
      seasonNumber: jsonInt(map['season_number']) ?? 0,
      episodeNumber: jsonInt(map['episode_number']) ?? 0,
      name: jsonString(map['name']),
      overview: jsonString(map['overview']),
      airDate: jsonDateTime(map['air_date']),
      stillUrl: jsonString(map['still_url']),
      runtime: jsonInt(map['runtime']),
      watched: map['watched'] == true,
      watchedAt: jsonDateTime(map['watched_at']),
      createdAt: jsonDateTime(map['created_at']),
    );
  }

  /// Primary key; `null` until the row has been inserted.
  final String? id;

  /// Owning `media_items.id`.
  final String mediaItemId;

  final int seasonNumber;
  final int episodeNumber;

  // Cached metadata.
  final String? name;
  final String? overview;
  final DateTime? airDate;
  final String? stillUrl;

  /// Runtime in minutes.
  final int? runtime;

  // Watch state.
  final bool watched;
  final DateTime? watchedAt;

  final DateTime? createdAt;

  Episode copyWith({
    String? id,
    String? mediaItemId,
    int? seasonNumber,
    int? episodeNumber,
    String? name,
    String? overview,
    DateTime? airDate,
    String? stillUrl,
    int? runtime,
    bool? watched,
    DateTime? watchedAt,
    DateTime? createdAt,
  }) {
    return Episode(
      id: id ?? this.id,
      mediaItemId: mediaItemId ?? this.mediaItemId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      name: name ?? this.name,
      overview: overview ?? this.overview,
      airDate: airDate ?? this.airDate,
      stillUrl: stillUrl ?? this.stillUrl,
      runtime: runtime ?? this.runtime,
      watched: watched ?? this.watched,
      watchedAt: watchedAt ?? this.watchedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Serialises the episode to PostgREST column names.
  ///
  /// `null` values are omitted so that Postgres defaults apply. Note that
  /// [watchedAt] is also omitted when unset — use
  /// [MediaRepository.setWatched] to explicitly clear it.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'media_item_id': mediaItemId,
      'season_number': seasonNumber,
      'episode_number': episodeNumber,
      if (name != null) 'name': name,
      if (overview != null) 'overview': overview,
      if (airDate != null) 'air_date': dateOnly(airDate!),
      if (stillUrl != null) 'still_url': stillUrl,
      if (runtime != null) 'runtime': runtime,
      'watched': watched,
      if (watchedAt != null) 'watched_at': isoDateTime(watchedAt),
      if (createdAt != null) 'created_at': isoDateTime(createdAt),
    };
  }

  @override
  String toString() => 'Episode(id: $id, S${seasonNumber}E$episodeNumber, '
      'watched: $watched)';
}
