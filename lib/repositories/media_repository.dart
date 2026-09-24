import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/episode.dart';
import '../models/json_utils.dart';
import '../models/media_item.dart';
import '../models/reading_log_entry.dart';

/// A Supabase failure translated into a message that is safe to show the user.
class MediaRepositoryException implements Exception {
  const MediaRepositoryException(this.message, {this.cause});

  /// User-facing, English message.
  final String message;

  /// The original error, kept for logging / debugging.
  final Object? cause;

  @override
  String toString() =>
      'MediaRepositoryException: $message${cause == null ? '' : ' ($cause)'}';
}

/// Data access for `media_items` and `episodes`.
///
/// RLS already restricts every query to the signed-in owner, but `user_id` is
/// `not null` **without** a default, so writes inject
/// `auth.currentUser!.id` explicitly.
///
/// There is no realtime/stream API on purpose — callers load on demand and
/// refresh manually (`RefreshIndicator` / refresh button).
class MediaRepository {
  /// The optional positional argument is only used by tests to inject a
  /// client; production code resolves [Supabase.instance.client] lazily.
  MediaRepository([this._client]);

  final SupabaseClient? _client;

  /// The Supabase client, resolved lazily so tests can subclass without a
  /// live backend.
  SupabaseClient get client => _client ?? Supabase.instance.client;

  /// The signed-in user's id, or a [MediaRepositoryException] when signed out.
  String _requireUserId() {
    final user = client.auth.currentUser;
    if (user == null) {
      throw const MediaRepositoryException('You are not signed in.');
    }
    return user.id;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // media_items
  // ───────────────────────────────────────────────────────────────────────────

  /// Loads every media item of the signed-in user, newest first.
  Future<List<MediaItem>> fetchAll() {
    return _guard(() async {
      final rows = await client
          .from('media_items')
          .select()
          .order('created_at', ascending: false);
      return rows.map(MediaItem.fromMap).toList();
    }, fallback: 'Could not load your library.');
  }

  /// Loads a single item by id.
  Future<MediaItem?> fetchById(String id) {
    return _guard(() async {
      final row = await client
          .from('media_items')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : MediaItem.fromMap(row);
    }, fallback: 'Could not load the item.');
  }

  /// Finds the first item that came from [externalSource] / [externalId]
  /// (e.g. `'tmdb'` / `'27205'`), or `null` when it is not tracked yet.
  ///
  /// Backs the "Already in your library" check before adding a search hit.
  Future<MediaItem?> findByExternal(String externalSource, String externalId) {
    return _guard(() async {
      final row = await client
          .from('media_items')
          .select()
          .eq('external_source', externalSource)
          .eq('external_id', externalId)
          .maybeSingle();
      return row == null ? null : MediaItem.fromMap(row);
    }, fallback: 'Could not check your library.');
  }

  /// Inserts [item] for the signed-in user and returns the stored row.
  Future<MediaItem> insert(MediaItem item) {
    final userId = _requireUserId();
    return _guard(() async {
      final payload = Map<String, dynamic>.from(item.toMap())
        ..['user_id'] = userId
        // Server-managed columns: let the defaults / trigger win.
        ..remove('created_at')
        ..remove('updated_at');
      final row = await client
          .from('media_items')
          .insert(payload)
          .select()
          .single();
      return MediaItem.fromMap(row);
    }, fallback: 'Could not add the item.');
  }

  /// Updates an existing item (matched by [MediaItem.id]) and returns the
  /// stored row.
  Future<MediaItem> update(MediaItem item) {
    final id = item.id;
    if (id == null) {
      throw const MediaRepositoryException(
        'Cannot update an item that has no id yet.',
      );
    }
    _requireUserId();
    return _guard(() async {
      final payload = Map<String, dynamic>.from(item.toMap())
        ..remove('id')
        ..remove('user_id')
        ..remove('created_at')
        ..remove('updated_at');
      final row = await client
          .from('media_items')
          .update(payload)
          .eq('id', id)
          .select()
          .single();
      return MediaItem.fromMap(row);
    }, fallback: 'Could not save the item.');
  }

  /// Updates **only the metadata columns** of [item] (matched by
  /// [MediaItem.id]) and returns the stored row.
  ///
  /// Used when a stored snapshot has to be refreshed in another language
  /// (TMDB): tracking state — `status`, progress, timestamps, `kind`, the
  /// external ids and `created_at` — is deliberately left untouched, and
  /// `updated_at` is set by the database trigger.
  ///
  /// [item] may carry a full copy of the row (it usually does, built via
  /// [MediaItem.copyWith]); only [kMetadataUpdateFields] are sent.
  Future<MediaItem> updateMetadata(MediaItem item) {
    final id = item.id;
    if (id == null) {
      throw const MediaRepositoryException(
        'Cannot update metadata of an item that has no id yet.',
      );
    }
    _requireUserId();
    return _guard(() async {
      final row = await client
          .from('media_items')
          .update(metadataUpdatePayload(item))
          .eq('id', id)
          .select()
          .single();
      return MediaItem.fromMap(row);
    }, fallback: 'Could not refresh the metadata.');
  }

  /// Deletes an item (its episodes cascade in Postgres).
  Future<void> delete(String id) {
    _requireUserId();
    return _guard(() async {
      await client.from('media_items').delete().eq('id', id);
    }, fallback: 'Could not delete the item.');
  }

  /// Deletes **every** media item of the signed-in user.
  ///
  /// Backs the "overwrite" import mode. The episodes cascade in Postgres
  /// (`ON DELETE CASCADE`), so a single statement clears the whole library.
  /// RLS already restricts the delete to the owner; the `id is not null`
  /// filter only satisfies PostgREST, which refuses an unfiltered delete.
  Future<void> deleteAll() {
    _requireUserId();
    return _guard(() async {
      await client.from('media_items').delete().not('id', 'is', null);
    }, fallback: 'Could not delete your data.');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // tracking state (Phase 3a)
  // ───────────────────────────────────────────────────────────────────────────

  /// Writes **only tracking columns** of the item with [id] and returns the
  /// stored row.
  ///
  /// [fields] must be a subset of [kTrackingUpdateFields]; anything else is
  /// rejected before a request is made, so a tracking change can never clobber
  /// the metadata snapshot (title, overview, poster, …) or the external ids.
  /// `null` values are sent on purpose — e.g. clearing `started_at` when the
  /// user resets an item to `planned`.
  Future<MediaItem> updateTracking(String id, Map<String, dynamic> fields) {
    final unknown = fields.keys
        .where((key) => !kTrackingUpdateFields.contains(key))
        .toList();
    if (unknown.isNotEmpty) {
      return Future<MediaItem>.error(
        MediaRepositoryException(
          'Refusing to write non-tracking column(s): ${unknown.join(', ')}.',
        ),
      );
    }
    _requireUserId();
    return _guard(() async {
      final row = await client
          .from('media_items')
          .update(Map<String, dynamic>.from(fields))
          .eq('id', id)
          .select()
          .single();
      return MediaItem.fromMap(row);
    }, fallback: 'Could not save the change.');
  }

  /// Sets `status` (and nothing else).
  Future<MediaItem> setStatus(String id, MediaStatus status) =>
      updateTracking(id, <String, dynamic>{'status': status.wire});

  /// Sets `progress_percent` (and only that column).
  Future<MediaItem> setProgressPercent(String id, double percent) =>
      updateTracking(id, <String, dynamic>{'progress_percent': percent});

  /// Sets `progress_current` — or clears it with `null`.
  Future<MediaItem> setProgressCurrent(String id, int? current) =>
      updateTracking(id, <String, dynamic>{'progress_current': current});

  /// Sets `started_at` — or clears it with `null`.
  Future<MediaItem> setStartedAt(String id, DateTime? value) => updateTracking(
    id,
    <String, dynamic>{'started_at': value?.toUtc().toIso8601String()},
  );

  /// Sets `completed_at` — or clears it with `null`.
  Future<MediaItem> setCompletedAt(String id, DateTime? value) =>
      updateTracking(id, <String, dynamic>{
        'completed_at': value?.toUtc().toIso8601String(),
      });

  /// Sets `total_pages` — or clears it with `null`.
  Future<MediaItem> setTotalPages(String id, int? value) =>
      updateTracking(id, <String, dynamic>{'total_pages': value});

  // ───────────────────────────────────────────────────────────────────────────
  // reading log
  // ───────────────────────────────────────────────────────────────────────────

  /// Appends one entry to the user's reading log and returns the stored row.
  ///
  /// [pages] is **signed** — a positive value is reading progress, a negative
  /// value a correction. `user_id` is injected from the signed-in session (not
  /// just relying on RLS) and `id` / `created_at` are left to the database.
  /// [loggedAt] defaults to `now()` in Postgres when omitted.
  Future<ReadingLogEntry> insertReadingLog({
    required String mediaItemId,
    required int pages,
    DateTime? loggedAt,
  }) {
    final userId = _requireUserId();
    return _guard(() async {
      final payload = <String, dynamic>{
        'user_id': userId,
        'media_item_id': mediaItemId,
        'pages': pages,
        if (loggedAt != null) 'logged_at': isoDateTime(loggedAt),
      };
      final row = await client
          .from('reading_log')
          .insert(payload)
          .select()
          .single();
      return ReadingLogEntry.fromMap(row);
    }, fallback: 'Could not save the reading log.');
  }

  /// Loads the user's reading log, oldest first.
  ///
  /// When [from] is given, only entries with `logged_at >= from` are returned.
  /// RLS restricts the query to the signed-in owner.
  Future<List<ReadingLogEntry>> fetchReadingLog({DateTime? from}) {
    return _guard(() async {
      var query = client.from('reading_log').select();
      if (from != null) {
        query = query.gte('logged_at', isoDateTime(from)!);
      }
      final rows = await query.order('logged_at', ascending: true);
      return rows.map(ReadingLogEntry.fromMap).toList();
    }, fallback: 'Could not load your reading log.');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // episodes
  // ───────────────────────────────────────────────────────────────────────────

  /// Loads all episodes of [mediaItemId] ordered by season/episode.
  Future<List<Episode>> fetchEpisodes(String mediaItemId) {
    return _guard(() async {
      final rows = await client
          .from('episodes')
          .select()
          .eq('media_item_id', mediaItemId)
          .order('season_number', ascending: true)
          .order('episode_number', ascending: true);
      return rows.map(Episode.fromMap).toList();
    }, fallback: 'Could not load the episodes.');
  }

  /// Loads **every** episode of the signed-in user, ordered by their parent
  /// item / season / episode.
  ///
  /// Backs the JSON export, which needs the full episode list in one request.
  /// RLS already restricts the query to the owner.
  Future<List<Episode>> fetchAllEpisodes() {
    return _guard(() async {
      final rows = await client
          .from('episodes')
          .select()
          .order('media_item_id', ascending: true)
          .order('season_number', ascending: true)
          .order('episode_number', ascending: true);
      return rows.map(Episode.fromMap).toList();
    }, fallback: 'Could not load your episodes.');
  }

  /// Inserts or updates [episodes] (matched on
  /// `media_item_id, season_number, episode_number`) and returns the stored
  /// rows.
  ///
  /// The **watch state is sent along** — this is the write used when episodes
  /// are first loaded and no row exists yet. For a metadata-only refresh use
  /// [upsertEpisodeMetadata] instead.
  Future<List<Episode>> upsertEpisodes(List<Episode> episodes) {
    if (episodes.isEmpty) return Future<List<Episode>>.value(const <Episode>[]);
    final userId = _requireUserId();
    return _guard(() async {
      final payloads = episodes
          .map(
            (episode) => Map<String, dynamic>.from(episode.toMap())
              ..['user_id'] = userId
              ..remove('created_at'),
          )
          .toList();
      final rows = await client
          .from('episodes')
          .upsert(
            payloads,
            onConflict: 'media_item_id,season_number,episode_number',
          )
          .select();
      return rows.map(Episode.fromMap).toList();
    }, fallback: 'Could not save the episodes.');
  }

  /// Upserts **only the metadata columns** of [episodes] (matched on
  /// `media_item_id, season_number, episode_number`).
  ///
  /// Used by the language-driven refresh: `watched` stays exactly as the user
  /// left it (the column is simply not part of the payload, so PostgREST
  /// leaves it untouched on an existing row and the `false` default applies to
  /// a row inserted for the first time).
  Future<List<Episode>> upsertEpisodeMetadata(List<Episode> episodes) {
    if (episodes.isEmpty) return Future<List<Episode>>.value(const <Episode>[]);
    final userId = _requireUserId();
    return _guard(() async {
      final payloads = episodes
          .map(
            (episode) => episodeMetadataPayload(episode)..['user_id'] = userId,
          )
          .toList();
      final rows = await client
          .from('episodes')
          .upsert(
            payloads,
            onConflict: 'media_item_id,season_number,episode_number',
          )
          .select();
      return rows.map(Episode.fromMap).toList();
    }, fallback: 'Could not save the episodes.');
  }

  /// Marks a single episode as watched / unwatched and returns the stored row.
  ///
  /// [watchedAt] is cleared explicitly when un-watching.
  Future<Episode> setWatched(String episodeId, bool watched) {
    _requireUserId();
    return _guard(() async {
      final row = await client
          .from('episodes')
          .update(<String, dynamic>{
            'watched': watched,
            'watched_at': watched
                ? DateTime.now().toUtc().toIso8601String()
                : null,
          })
          .eq('id', episodeId)
          .select()
          .single();
      return Episode.fromMap(row);
    }, fallback: 'Could not update the episode.');
  }

  /// Marks **every episode of a season** of [mediaItemId] as watched and
  /// returns the updated rows.
  Future<List<Episode>> markSeasonWatched(
    String mediaItemId,
    int seasonNumber,
  ) => _updateSeasonWatchState(mediaItemId, seasonNumber, watched: true);

  /// Clears the watched state of **every episode of a season** and returns the
  /// updated rows.
  Future<List<Episode>> resetSeason(String mediaItemId, int seasonNumber) =>
      _updateSeasonWatchState(mediaItemId, seasonNumber, watched: false);

  Future<List<Episode>> _updateSeasonWatchState(
    String mediaItemId,
    int seasonNumber, {
    required bool watched,
  }) {
    _requireUserId();
    return _guard(() async {
      final rows = await client
          .from('episodes')
          .update(<String, dynamic>{
            'watched': watched,
            'watched_at': watched
                ? DateTime.now().toUtc().toIso8601String()
                : null,
          })
          .eq('media_item_id', mediaItemId)
          .eq('season_number', seasonNumber)
          .select();
      return rows.map(Episode.fromMap).toList();
    }, fallback: 'Could not update the season.');
  }

  /// Deletes a single episode.
  Future<void> deleteEpisode(String episodeId) {
    _requireUserId();
    return _guard(() async {
      await client.from('episodes').delete().eq('id', episodeId);
    }, fallback: 'Could not delete the episode.');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // error handling
  // ───────────────────────────────────────────────────────────────────────────

  Future<T> _guard<T>(
    Future<T> Function() action, {
    required String fallback,
  }) async {
    try {
      return await action();
    } on MediaRepositoryException {
      rethrow;
    } on PostgrestException catch (error) {
      throw MediaRepositoryException(
        describePostgrestError(error, fallback: fallback),
        cause: error,
      );
    } on AuthException catch (error) {
      throw MediaRepositoryException(error.message, cause: error);
    } catch (error) {
      throw MediaRepositoryException(fallback, cause: error);
    }
  }
}

/// The **only** columns a tracking write may touch.
///
/// Everything else on `media_items` — the metadata snapshot, ownership, `kind`,
/// the external ids and `created_at`/`updated_at` — is out of bounds for a
/// tracking change (see [MediaRepository.updateTracking]); `updated_at` is set
/// by the database trigger.
const Set<String> kTrackingUpdateFields = <String>{
  'status',
  'progress_percent',
  'progress_current',
  'started_at',
  'completed_at',
  'total_pages',
};

/// The **only** columns a metadata refresh may touch.
///
/// Everything else on `media_items` (tracking state, ownership, kind, the
/// external ids, timestamps) belongs to the user or the server.
const Set<String> kMetadataUpdateFields = <String>{
  'title',
  'original_title',
  'release_year',
  'overview',
  'poster_url',
  'total_seasons',
  'total_episodes',
  'runtime',
};

/// Builds the PostgREST payload for [MediaRepository.updateMetadata].
///
/// Nullable columns are sent as `null` on purpose: a language in which TMDB
/// has no overview (or poster) must be able to clear a stale one. The set of
/// keys is exactly [kMetadataUpdateFields] — see the guard test.
Map<String, dynamic> metadataUpdatePayload(MediaItem item) {
  return <String, dynamic>{
    'title': item.title,
    'original_title': item.originalTitle,
    'release_year': item.releaseYear,
    'overview': item.overview,
    'poster_url': item.posterUrl,
    'total_seasons': item.totalSeasons,
    'total_episodes': item.totalEpisodes,
    'runtime': item.runtime,
  };
}

/// The **only** columns an episode metadata refresh may touch.
///
/// The watch state (`watched`, `watched_at`) and the identity columns
/// (`id`, `user_id`, `created_at`) are out of bounds — see
/// [MediaRepository.upsertEpisodeMetadata].
const Set<String> kEpisodeMetadataFields = <String>{
  'media_item_id',
  'season_number',
  'episode_number',
  'name',
  'overview',
  'air_date',
  'still_url',
  'runtime',
};

/// Builds the PostgREST payload for
/// [MediaRepository.upsertEpisodeMetadata] — exactly [kEpisodeMetadataFields],
/// never the watch state. Nullable columns are sent as `null` so a language
/// without a localized title/overview/still can clear a stale one.
Map<String, dynamic> episodeMetadataPayload(Episode episode) {
  return <String, dynamic>{
    'media_item_id': episode.mediaItemId,
    'season_number': episode.seasonNumber,
    'episode_number': episode.episodeNumber,
    'name': episode.name,
    'overview': episode.overview,
    'air_date': episode.airDate == null ? null : dateOnly(episode.airDate!),
    'still_url': episode.stillUrl,
    'runtime': episode.runtime,
  };
}

/// Maps a [PostgrestException] to a user-facing message.
///
/// The raw Postgres message is appended where it adds signal (constraint
/// violations, missing schema) — it never contains secrets.
String describePostgrestError(
  PostgrestException error, {
  required String fallback,
}) {
  switch (error.code) {
    case 'PGRST205': // table not in the schema cache
      return 'The database schema is not set up yet. Run '
          'supabase/migrations/0001_init.sql in the Supabase SQL editor.';
    case '42501': // insufficient privilege (RLS / missing grant)
      return 'You do not have access to this data. Try signing in again.';
    case '23505': // unique violation
      return 'This item is already in your library.';
    case '23503': // foreign key violation
      return 'The related item no longer exists.';
    case '23514': // check constraint violation
      return 'One of the values is not allowed.';
  }
  return '$fallback (${error.message})';
}
