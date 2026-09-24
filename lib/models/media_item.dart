import 'json_utils.dart';

/// The three kinds of media the app tracks (`media_items.kind`).
enum MediaKind {
  movie('movie', 'Movie'),
  series('series', 'Series'),
  book('book', 'Book');

  const MediaKind(this.wire, this.label);

  /// The value stored in Postgres.
  final String wire;

  /// Human readable label for the UI.
  final String label;

  /// Parses a Postgres value, throwing [FormatException] on unknown input.
  static MediaKind fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    throw FormatException('Unknown media kind: $value');
  }
}

/// Tracking status of a media item (`media_items.status`).
enum MediaStatus {
  planned('planned', 'Planned'),
  inProgress('in_progress', 'In progress'),
  completed('completed', 'Completed'),
  dropped('dropped', 'Dropped');

  const MediaStatus(this.wire, this.label);

  /// The value stored in Postgres.
  final String wire;

  /// Human readable label for the UI.
  final String label;

  /// Parses a Postgres value, throwing [FormatException] on unknown input.
  static MediaStatus fromWire(Object? value) {
    for (final status in values) {
      if (status.wire == value) return status;
    }
    throw FormatException('Unknown media status: $value');
  }
}

/// A row of `public.media_items` — metadata snapshot *and* tracking state.
///
/// `user_id` is deliberately **not** part of the model: ownership is injected
/// by [MediaRepository] on write and enforced by RLS on read.
class MediaItem {
  const MediaItem({
    this.id,
    required this.kind,
    required this.title,
    this.originalTitle,
    this.releaseYear,
    this.overview,
    this.posterUrl,
    this.externalSource,
    this.externalId,
    this.authors = const <String>[],
    this.totalPages,
    this.isbn,
    this.totalSeasons,
    this.totalEpisodes,
    this.runtime,
    this.status = MediaStatus.planned,
    this.progressPercent,
    this.progressCurrent,
    this.startedAt,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Builds an item from a PostgREST row.
  factory MediaItem.fromMap(Map<String, dynamic> map) {
    return MediaItem(
      id: jsonString(map['id']),
      kind: MediaKind.fromWire(map['kind']),
      title: jsonString(map['title']) ?? '',
      originalTitle: jsonString(map['original_title']),
      releaseYear: jsonInt(map['release_year']),
      overview: jsonString(map['overview']),
      posterUrl: jsonString(map['poster_url']),
      externalSource: jsonString(map['external_source']),
      externalId: jsonString(map['external_id']),
      authors: jsonStringList(map['authors']),
      totalPages: jsonInt(map['total_pages']),
      isbn: jsonString(map['isbn']),
      totalSeasons: jsonInt(map['total_seasons']),
      totalEpisodes: jsonInt(map['total_episodes']),
      runtime: jsonInt(map['runtime']),
      status: map['status'] == null
          ? MediaStatus.planned
          : MediaStatus.fromWire(map['status']),
      progressPercent: jsonDouble(map['progress_percent']),
      progressCurrent: jsonInt(map['progress_current']),
      startedAt: jsonDateTime(map['started_at']),
      completedAt: jsonDateTime(map['completed_at']),
      createdAt: jsonDateTime(map['created_at']),
      updatedAt: jsonDateTime(map['updated_at']),
    );
  }

  /// Primary key; `null` until the row has been inserted.
  final String? id;

  final MediaKind kind;
  final String title;
  final String? originalTitle;
  final int? releaseYear;
  final String? overview;
  final String? posterUrl;

  /// `'tmdb'` or `'openlibrary'` (or anything manual, e.g. `null`).
  final String? externalSource;
  final String? externalId;

  // Book specific.
  final List<String> authors;
  final int? totalPages;
  final String? isbn;

  // Series specific.
  final int? totalSeasons;
  final int? totalEpisodes;

  /// Runtime in minutes — **movies only** (series/books leave this `null`;
  /// a series' episode runtimes live on `episodes.runtime`).
  ///
  /// Backfilled by the TMDB detail request when an item is added and by the
  /// metadata refresh; existing rows stay `null` until then.
  final int? runtime;

  // Tracking state.
  final MediaStatus status;

  /// `0..100`.
  final double? progressPercent;

  /// Current page (book) or episode number (series).
  final int? progressCurrent;
  final DateTime? startedAt;
  final DateTime? completedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether a poster is available for the list thumbnail.
  bool get hasPoster => posterUrl != null && posterUrl!.isNotEmpty;

  MediaItem copyWith({
    String? id,
    MediaKind? kind,
    String? title,
    String? originalTitle,
    int? releaseYear,
    String? overview,
    String? posterUrl,
    String? externalSource,
    String? externalId,
    List<String>? authors,
    int? totalPages,
    String? isbn,
    int? totalSeasons,
    int? totalEpisodes,
    int? runtime,
    MediaStatus? status,
    double? progressPercent,
    int? progressCurrent,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MediaItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      releaseYear: releaseYear ?? this.releaseYear,
      overview: overview ?? this.overview,
      posterUrl: posterUrl ?? this.posterUrl,
      externalSource: externalSource ?? this.externalSource,
      externalId: externalId ?? this.externalId,
      authors: authors ?? this.authors,
      totalPages: totalPages ?? this.totalPages,
      isbn: isbn ?? this.isbn,
      totalSeasons: totalSeasons ?? this.totalSeasons,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      runtime: runtime ?? this.runtime,
      status: status ?? this.status,
      progressPercent: progressPercent ?? this.progressPercent,
      progressCurrent: progressCurrent ?? this.progressCurrent,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// A copy **without** the server-managed identity columns (`id`,
  /// `createdAt`, `updatedAt`).
  ///
  /// Used by the JSON import: the export carries the original ids so episodes
  /// can be re-linked, but the database must assign fresh ones (and the
  /// current user) on insert — see `DataPortService.importData`.
  MediaItem asNew() {
    return MediaItem(
      kind: kind,
      title: title,
      originalTitle: originalTitle,
      releaseYear: releaseYear,
      overview: overview,
      posterUrl: posterUrl,
      externalSource: externalSource,
      externalId: externalId,
      authors: authors,
      totalPages: totalPages,
      isbn: isbn,
      totalSeasons: totalSeasons,
      totalEpisodes: totalEpisodes,
      runtime: runtime,
      status: status,
      progressPercent: progressPercent,
      progressCurrent: progressCurrent,
      startedAt: startedAt,
      completedAt: completedAt,
    );
  }

  /// Serialises the item to PostgREST column names.
  ///
  /// `null` values are omitted so that Postgres defaults apply (notably
  /// `created_at` / `updated_at`, which are `not null` and server-managed).
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'kind': kind.wire,
      'title': title,
      if (originalTitle != null) 'original_title': originalTitle,
      if (releaseYear != null) 'release_year': releaseYear,
      if (overview != null) 'overview': overview,
      if (posterUrl != null) 'poster_url': posterUrl,
      if (externalSource != null) 'external_source': externalSource,
      if (externalId != null) 'external_id': externalId,
      if (authors.isNotEmpty) 'authors': authors,
      if (totalPages != null) 'total_pages': totalPages,
      if (isbn != null) 'isbn': isbn,
      if (totalSeasons != null) 'total_seasons': totalSeasons,
      if (totalEpisodes != null) 'total_episodes': totalEpisodes,
      if (runtime != null) 'runtime': runtime,
      'status': status.wire,
      if (progressPercent != null) 'progress_percent': progressPercent,
      if (progressCurrent != null) 'progress_current': progressCurrent,
      if (startedAt != null) 'started_at': isoDateTime(startedAt),
      if (completedAt != null) 'completed_at': isoDateTime(completedAt),
      if (createdAt != null) 'created_at': isoDateTime(createdAt),
      if (updatedAt != null) 'updated_at': isoDateTime(updatedAt),
    };
  }

  @override
  String toString() =>
      'MediaItem(id: $id, kind: ${kind.wire}, title: $title, '
      'status: ${status.wire})';
}
