import 'json_utils.dart';

/// A row of `public.reading_log` — how many pages were read when.
///
/// The reading log records the **delta** of a book's page position every time
/// it changes (a slider is released, a page is submitted, a status change moves
/// the position). It is what makes \"pages read in a period\" exact instead of
/// approximating it from completed books.
///
/// [pages] is deliberately **signed**:
///
///  * a positive value is reading progress (120 → 200 logs `+80`),
///  * a negative value is a correction (200 → 180 logs `-20`, a reset to
///    `planned` logs `-200`),
///  * a change of `0` is never logged at all.
///
/// `user_id` is not part of the tracking models' write path, but unlike
/// [MediaItem] / [Episode] it is kept on the model because a reading entry is
/// meaningless without knowing whose log it is (and the repository always
/// injects the signed-in user on write, see `MediaRepository.insertReadingLog`).
class ReadingLogEntry {
  const ReadingLogEntry({
    this.id,
    this.userId,
    required this.mediaItemId,
    required this.pages,
    this.loggedAt,
    this.createdAt,
  });

  /// Builds an entry from a PostgREST row.
  ///
  /// Tolerant like every other model: a missing / malformed field never
  /// throws. [loggedAt] stays `null` when the row has no usable timestamp —
  /// the stats then simply skip the entry instead of dating it to 1970.
  factory ReadingLogEntry.fromMap(Map<String, dynamic> map) {
    return ReadingLogEntry(
      id: jsonString(map['id']),
      userId: jsonString(map['user_id']),
      mediaItemId: jsonString(map['media_item_id']) ?? '',
      pages: jsonInt(map['pages']) ?? 0,
      loggedAt: jsonDateTime(map['logged_at']),
      createdAt: jsonDateTime(map['created_at']),
    );
  }

  /// Primary key; `null` until the row has been inserted.
  final String? id;

  /// Owning `auth.users.id` — injected from the session on write (RLS).
  final String? userId;

  /// Owning `media_items.id`.
  final String mediaItemId;

  /// Signed page delta — negative values are corrections.
  final int pages;

  /// When the reading happened (`reading_log.logged_at`, `not null` in the
  /// database). `null` only when a row was built from an incomplete map.
  final DateTime? loggedAt;

  final DateTime? createdAt;

  ReadingLogEntry copyWith({
    String? id,
    String? userId,
    String? mediaItemId,
    int? pages,
    DateTime? loggedAt,
    DateTime? createdAt,
  }) {
    return ReadingLogEntry(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      mediaItemId: mediaItemId ?? this.mediaItemId,
      pages: pages ?? this.pages,
      loggedAt: loggedAt ?? this.loggedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// A copy **without** the server-managed / owner columns (`id`, `userId`,
  /// `createdAt`) so the database assigns a fresh id and the repository
  /// injects the signed-in user.
  ReadingLogEntry asNew() {
    return ReadingLogEntry(
      mediaItemId: mediaItemId,
      pages: pages,
      loggedAt: loggedAt,
    );
  }

  /// Serialises the entry to PostgREST column names.
  ///
  /// `null` values are omitted so the Postgres defaults apply (`id`, `user_id`
  /// and `created_at` are server-managed; `logged_at` defaults to `now()`).
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      'media_item_id': mediaItemId,
      'pages': pages,
      if (loggedAt != null) 'logged_at': isoDateTime(loggedAt),
      if (createdAt != null) 'created_at': isoDateTime(createdAt),
    };
  }

  @override
  String toString() =>
      'ReadingLogEntry(id: $id, mediaItemId: $mediaItemId, pages: $pages, '
      'loggedAt: $loggedAt)';
}
