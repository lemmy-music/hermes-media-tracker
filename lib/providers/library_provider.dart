import 'package:flutter/foundation.dart';

import '../l10n/app_language.dart';
import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/tmdb_result.dart';
import '../repositories/media_repository.dart';
import '../services/tmdb_client.dart';
import 'series_rules.dart';
import 'settings_provider.dart';
import 'tracking_rules.dart';

/// Outcome of one metadata refresh run.
///
/// The counters describe **media items**, not requests: `total` is the number
/// of TMDB-backed library entries, `updated` those whose metadata snapshot was
/// re-fetched and stored, `failed` those that kept their snapshot because
/// loading or saving failed.
///
/// Series additionally have their **episodes** refreshed in the new language
/// as part of the item's own update (see [LibraryProvider.refreshMetadata]).
/// A failing season request there is skipped and deliberately does **not**
/// count as a failure — it does not abort the run and never fails the item,
/// whose primary metadata was already written.
@immutable
class MetadataRefreshResult {
  const MetadataRefreshResult({
    required this.updated,
    required this.total,
    required this.failed,
  });

  /// Items whose metadata was re-fetched and stored.
  final int updated;

  /// Items that were candidates for a refresh (`external_source == 'tmdb'`).
  final int total;

  /// Items that kept their stored snapshot because loading or saving failed.
  final int failed;

  /// `true` when there was at least one TMDB item to refresh.
  bool get hadCandidates => total > 0;

  /// `true` when at least one item kept its (possibly stale) metadata.
  bool get hadFailures => failed > 0;

  /// A run that found nothing to do.
  static const MetadataRefreshResult empty = MetadataRefreshResult(
    updated: 0,
    total: 0,
    failed: 0,
  );

  @override
  String toString() =>
      'MetadataRefreshResult(updated: $updated, total: $total, '
      'failed: $failed)';
}

/// Holds the library list **and** the language-driven metadata refresh.
///
/// Metadata (title, overview, poster, …) is stored as a snapshot in the
/// language that was active when the item was added. Switching the UI
/// language therefore has to re-fetch the TMDB details of every stored TMDB
/// item — otherwise an English "The Lord of the Rings" stays English in a
/// German library (and it cannot be re-added: the `external_id` unique index
/// would reject it).
///
/// The provider listens to [SettingsProvider]: an actual language change
/// starts a refresh in the background. Tracking state is never touched; see
/// [MediaRepository.updateMetadata].
class LibraryProvider extends ChangeNotifier {
  LibraryProvider({
    required MediaRepository repository,
    required TmdbClient tmdbClient,
    required SettingsProvider settings,
    int maxConcurrency = defaultMaxConcurrency,
    DateTime Function()? clock,
  }) : // The two fields below are private and their parameter names must stay
       // public, so an initializing formal is impossible here — the lint is a
       // false positive.
       // ignore: prefer_initializing_formals
       _repository = repository,
       // ignore: prefer_initializing_formals
       _tmdbClient = tmdbClient,
       _settings = settings,
       _language = settings.language,
       _clock = clock ?? DateTime.now,
       _maxConcurrency = maxConcurrency < 1 ? 1 : maxConcurrency {
    _settings.addListener(_onSettingsChanged);
  }

  /// The `external_source` value of TMDB-backed items.
  static const String tmdbSource = 'tmdb';

  /// How many TMDB requests run at the same time. TMDB happily serves a
  /// handful of parallel requests, but the run must stay gentle.
  static const int defaultMaxConcurrency = 4;

  final MediaRepository _repository;
  final TmdbClient _tmdbClient;
  final SettingsProvider _settings;
  final int _maxConcurrency;

  /// Injectable clock — production uses [DateTime.now], tests pin it so the
  /// auto-filled timestamps are deterministic.
  final DateTime Function() _clock;

  /// The language the metadata currently reflects — the provider refreshes
  /// whenever [SettingsProvider] moves away from it.
  AppLanguage _language;

  List<MediaItem> _items = const <MediaItem>[];
  bool _loading = true;
  String? _error;

  bool _refreshingMetadata = false;
  int _metadataRefreshDone = 0;
  int _metadataRefreshTotal = 0;
  int _metadataRefreshRuns = 0;
  AppLanguage? _metadataRefreshLanguage;
  MetadataRefreshResult? _lastMetadataRefresh;
  Future<MetadataRefreshResult>? _activeRefresh;

  bool _disposed = false;

  // ── series episodes (Phase 3b) ─────────────────────────────────────────────
  //
  // Episodes are cached per media item. The metadata is loaded lazily on the
  // first open of a series detail view and only re-fetched on an explicit
  // refresh or a language change — never per navigation.

  /// Episodes of a media item, ordered by season / episode.
  final Map<String, List<Episode>> _episodesByItem = <String, List<Episode>>{};

  /// Item ids whose episodes have been loaded (even when the result was empty,
  /// so an empty series is not re-fetched on every open).
  final Set<String> _episodesLoaded = <String>{};

  /// Item ids with an episode load in flight (guards against a second run).
  final Set<String> _episodesActive = <String>{};

  /// Item ids currently loading episodes from TMDB.
  final Set<String> _episodesLoading = <String>{};

  /// Per-item progress of the current TMDB load (seasons handled / total).
  final Map<String, int> _episodesLoadDone = <String, int>{};
  final Map<String, int> _episodesLoadTotal = <String, int>{};

  /// Per-item user-facing load error, if the last attempt failed.
  final Map<String, String> _episodesError = <String, String>{};

  // ───────────────────────────────────────────────────────────────────────────
  // library list
  // ───────────────────────────────────────────────────────────────────────────

  /// The loaded items, newest first (as returned by the repository).
  List<MediaItem> get items => _items;

  /// `true` while the list is being (re)loaded.
  bool get loading => _loading;

  /// User-facing message of the last failed load, or `null`.
  String? get error => _error;

  /// Loads (or reloads) the signed-in user's library.
  Future<void> load() async {
    if (!_loading || _error != null) {
      _loading = true;
      _error = null;
      _notify();
    }
    try {
      final items = await _repository.fetchAll();
      _items = items;
      _loading = false;
    } on MediaRepositoryException catch (error) {
      _error = error.message;
      _loading = false;
    }
    _notify();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // tracking (Phase 3a — movies & books)
  // ───────────────────────────────────────────────────────────────────────────

  /// The loaded item with [id], or `null` when it is not (or no longer) in the
  /// list. Backs the live detail view, which must not work on a stale copy.
  MediaItem? itemById(String? id) {
    if (id == null) return null;
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Changes [item]'s status.
  ///
  /// The columns are computed by [statusChangeFields] — `in_progress` fills a
  /// missing `started_at`, `completed` fills a missing `completed_at` and forces
  /// 100 %, `planned` resets the progress and clears both timestamps. Manually
  /// entered values are never overwritten.
  Future<MediaItem> setStatus(MediaItem item, MediaStatus status) =>
      _applyTracking(item, statusChangeFields(item, status, now: _clock()));

  /// Sets the percent progress of a movie or a book.
  ///
  /// Reaching 100 % also completes the item (unless it was dropped).
  Future<MediaItem> setProgressPercent(MediaItem item, num percent) =>
      _applyTracking(item, progressPercentFields(item, percent, now: _clock()));

  /// Sets the current page of a book with a known page count.
  ///
  /// The percent value is derived and stored alongside it; the last page
  /// completes the item (unless it was dropped).
  Future<MediaItem> setProgressPage(MediaItem item, int page) =>
      _applyTracking(item, progressPageFields(item, page, now: _clock()));

  /// Sets (or clears) the "started on" timestamp manually — Daniel wants to be
  /// able to back-date an entry.
  Future<MediaItem> setStartedAt(MediaItem item, DateTime? value) =>
      _applyTracking(item, startedAtFields(value));

  /// Sets (or clears) the "completed on" timestamp manually.
  Future<MediaItem> setCompletedAt(MediaItem item, DateTime? value) =>
      _applyTracking(item, completedAtFields(value));

  /// Sets (or clears) a book's total page count.
  Future<MediaItem> setTotalPages(MediaItem item, int? value) =>
      _applyTracking(item, totalPagesFields(item, value));

  /// Removes [item] from the library.
  Future<void> deleteItem(MediaItem item) async {
    final id = _requireId(item);
    await _repository.delete(id);
    _items = _items.where((candidate) => candidate.id != id).toList();
    _notify();
  }

  /// Writes [fields], swaps the stored row into the list and notifies — so the
  /// library list and the detail view both reflect the change immediately.
  Future<MediaItem> _applyTracking(
    MediaItem item,
    Map<String, dynamic> fields,
  ) async {
    final updated = await _repository.updateTracking(_requireId(item), fields);
    _replace(updated);
    return updated;
  }

  /// Replaces the stored copy of [item] (matched by id), keeping the list order.
  void _replace(MediaItem item) {
    final id = item.id;
    if (id == null) return;
    final index = _items.indexWhere((candidate) => candidate.id == id);
    if (index == -1) {
      // Not in the list (e.g. loaded elsewhere) — append so it stays visible.
      _items = <MediaItem>[..._items, item];
    } else {
      final next = List<MediaItem>.of(_items)..[index] = item;
      _items = next;
    }
    _notify();
  }

  String _requireId(MediaItem item) {
    final id = item.id;
    if (id == null) {
      throw const MediaRepositoryException('This item has not been saved yet.');
    }
    return id;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // series episodes (Phase 3b)
  // ───────────────────────────────────────────────────────────────────────────

  /// The cached episodes of [itemId] (empty when not loaded yet).
  List<Episode> episodesFor(String? itemId) {
    if (itemId == null) return const <Episode>[];
    return _episodesByItem[itemId] ?? const <Episode>[];
  }

  /// `true` while episodes of [itemId] are being loaded from TMDB.
  bool episodesLoading(String? itemId) =>
      itemId != null && _episodesLoading.contains(itemId);

  /// Seasons already handled in the current load of [itemId].
  int episodesLoadDone(String? itemId) => _episodesLoadDone[itemId] ?? 0;

  /// Seasons to handle in the current load of [itemId] (`0` while unknown).
  int episodesLoadTotal(String? itemId) => _episodesLoadTotal[itemId] ?? 0;

  /// The user-facing message of the last failed episode load, or `null`.
  String? episodesError(String? itemId) =>
      itemId == null ? null : _episodesError[itemId];

  /// The distinct season numbers of [itemId], ascending (season `0` = specials
  /// is excluded by the loader, see [_regularSeasonNumbers]).
  List<int> seasonsFor(String? itemId) {
    final numbers = <int>{
      for (final episode in episodesFor(itemId)) episode.seasonNumber,
    }.toList();
    numbers.sort();
    return numbers;
  }

  /// The episodes of [itemId] that belong to [seasonNumber].
  List<Episode> episodesOfSeason(String? itemId, int seasonNumber) =>
      episodesFor(
        itemId,
      ).where((episode) => episode.seasonNumber == seasonNumber).toList();

  /// Ensures the episodes of [item] are loaded.
  ///
  /// Lazy by design:
  ///  * Stored rows are used as-is (no TMDB request).
  ///  * Only when the database holds **no** episodes yet are seasons/following
  ///    episodes fetched from TMDB and persisted (metadata only — a fresh row
  ///    starts unwatched). Specials (season `0`) are skipped, see
  ///    [_regularSeasonNumbers].
  ///  * A second call while a load is running (or after a successful one) is a
  ///    no-op; use [refreshEpisodes] for a forced reload.
  Future<void> ensureEpisodes(MediaItem item) async {
    final id = item.id;
    if (id == null) return;
    if (_episodesLoaded.contains(id) || _episodesActive.contains(id)) return;
    _episodesActive.add(id);
    try {
      List<Episode> stored;
      try {
        stored = await _repository.fetchEpisodes(id);
      } on MediaRepositoryException catch (error) {
        _episodesError[id] = error.message;
        return;
      }
      if (stored.isNotEmpty) {
        _episodesByItem[id] = stored;
        _episodesLoaded.add(id);
        _episodesError.remove(id);
        _notify();
        // Keep the derived status/progress in sync with the stored episodes
        // (only writes when something actually changed).
        await _persistDerivedSafely(item, stored);
        return;
      }
      await _loadEpisodesFromTmdb(item);
    } finally {
      _episodesActive.remove(id);
    }
  }

  /// Forces a reload of [item]'s episode metadata from TMDB in the active
  /// language, preserving the stored watch state.
  ///
  /// Used by the manual refresh action on the series detail view.
  Future<void> refreshEpisodes(MediaItem item) async {
    final id = item.id;
    if (id == null || _episodesActive.contains(id)) return;
    _episodesActive.add(id);
    _episodesLoaded.remove(id);
    try {
      await _loadEpisodesFromTmdb(item);
    } finally {
      _episodesActive.remove(id);
    }
  }

  /// Toggles the watched state of a single [episode] and persists the derived
  /// series status / progress.
  Future<void> setEpisodeWatched(
    MediaItem item,
    Episode episode,
    bool watched,
  ) async {
    final itemId = _requireId(item);
    final episodeId = episode.id;
    if (episodeId == null) {
      throw const MediaRepositoryException('This episode has not been saved.');
    }
    final updated = await _repository.setWatched(episodeId, watched);
    _mergeEpisodes(itemId, <Episode>[updated]);
    await _persistDerived(item, episodesFor(itemId));
  }

  /// Marks **every** episode of [seasonNumber] as watched.
  Future<void> markSeasonWatched(MediaItem item, int seasonNumber) async {
    final itemId = _requireId(item);
    final updated = await _repository.markSeasonWatched(itemId, seasonNumber);
    _mergeEpisodes(itemId, updated);
    await _persistDerived(item, episodesFor(itemId));
  }

  /// Clears the watched state of every episode of [seasonNumber].
  Future<void> resetSeason(MediaItem item, int seasonNumber) async {
    final itemId = _requireId(item);
    final updated = await _repository.resetSeason(itemId, seasonNumber);
    _mergeEpisodes(itemId, updated);
    await _persistDerived(item, episodesFor(itemId));
  }

  /// Loads [item]'s seasons from TMDB, persists the metadata and fills the
  /// cache. The stored watch state of already-known episodes is preserved.
  ///
  /// A failing season request is skipped (and the run continues) — a series
  /// with at least one successful season loads; a run where *nothing* could be
  /// loaded surfaces a retry-able error.
  Future<void> _loadEpisodesFromTmdb(MediaItem item) async {
    final id = item.id;
    if (id == null) return;

    _episodesLoading.add(id);
    _episodesLoadDone[id] = 0;
    _episodesLoadTotal[id] = 0;
    _episodesError.remove(id);
    _notify();

    try {
      final tmdbId = int.tryParse(item.externalId ?? '');
      if (tmdbId == null) {
        // Not a TMDB-backed series — nothing to load, but do not retry.
        _episodesByItem[id] = const <Episode>[];
        _episodesLoaded.add(id);
        return;
      }

      final language = _settings.language.tmdbCode;
      final details = await _tmdbClient.fetchTv(tmdbId, language: language);

      // The stored state (empty during the first load) keyed by season:episode.
      final previous = <String, Episode>{
        for (final episode in episodesFor(id))
          '${episode.seasonNumber}:${episode.episodeNumber}': episode,
      };

      final seasonNumbers = _regularSeasonNumbers(details, item);
      _episodesLoadTotal[id] = seasonNumbers.length;
      _notify();

      final collected = <Episode>[];
      var failures = 0;
      String? lastFailure;

      for (final seasonNumber in seasonNumbers) {
        try {
          final season = await _tmdbClient.fetchSeason(
            tmdbId,
            seasonNumber,
            language: language,
          );
          final previousFor = previous;
          collected.addAll(<Episode>[
            for (final episode in season.episodes)
              _episodeFromTmdb(
                id,
                seasonNumber,
                episode,
                previous: previousFor['$seasonNumber:${episode.episodeNumber}'],
              ),
          ]);
        } catch (error) {
          failures++;
          lastFailure = error is TmdbException
              ? error.message
              : error.toString();
        } finally {
          _episodesLoadDone[id] = (_episodesLoadDone[id] ?? 0) + 1;
          _notify();
        }
      }

      if (collected.isEmpty && failures > 0) {
        _episodesError[id] = lastFailure ?? 'Could not load the episodes.';
        return;
      }

      if (collected.isNotEmpty) {
        // Metadata-only upsert: the watch state is never part of the payload.
        final saved = await _repository.upsertEpisodeMetadata(collected);
        _episodesByItem[id] = saved.isEmpty ? collected : _sorted(saved);
      } else {
        _episodesByItem[id] = const <Episode>[];
      }
      _episodesLoaded.add(id);
      _episodesError.remove(id);
      _notify();
      await _persistDerivedSafely(item, episodesFor(id));
    } on TmdbException catch (error) {
      _episodesError[id] = error.message;
    } on MediaRepositoryException catch (error) {
      _episodesError[id] = error.message;
    } finally {
      _episodesLoading.remove(id);
      _notify();
    }
  }

  /// The season numbers to fetch: every **numbered** season TMDB reports
  /// (`season_number >= 1`), falling back to `1..number_of_seasons` when the
  /// API response has no usable `seasons` array.
  ///
  /// **Specials (season `0`) are deliberately excluded**: they are behind-the-
  /// scenes extras rather than part of the main watch order, they would skew
  /// the derived percent, and they are frequently empty. Documented in
  /// PROJECT.md.
  List<int> _regularSeasonNumbers(TmdbTvDetails details, MediaItem item) {
    final numbered = <int>{
      for (final season in details.seasons)
        if (season.seasonNumber >= 1) season.seasonNumber,
    }.toList();
    if (numbered.isNotEmpty) {
      numbered.sort();
      return numbered;
    }
    final count = details.numberOfSeasons ?? item.totalSeasons ?? 0;
    if (count > 0) return <int>[for (var i = 1; i <= count; i++) i];
    return const <int>[];
  }

  /// Builds an [Episode] from a TMDB episode, keeping the watch state of
  /// [previous] (when an episode with the same season/number is already known).
  Episode _episodeFromTmdb(
    String mediaItemId,
    int seasonNumber,
    TmdbEpisode episode, {
    Episode? previous,
  }) {
    return Episode(
      id: previous?.id,
      mediaItemId: mediaItemId,
      seasonNumber: seasonNumber,
      episodeNumber: episode.episodeNumber,
      name: episode.name,
      overview: episode.overview,
      airDate: episode.airDate,
      stillUrl: episode.stillUrl,
      runtime: episode.runtime,
      watched: previous?.watched ?? false,
      watchedAt: previous?.watchedAt,
      createdAt: previous?.createdAt,
    );
  }

  /// Replaces the episodes of [itemId] that match [updated] (by season /
  /// episode) and keeps the list sorted.
  void _mergeEpisodes(String itemId, List<Episode> updated) {
    if (updated.isEmpty) return;
    final current = List<Episode>.of(episodesFor(itemId));
    for (final episode in updated) {
      final index = current.indexWhere(
        (candidate) =>
            candidate.seasonNumber == episode.seasonNumber &&
            candidate.episodeNumber == episode.episodeNumber,
      );
      if (index == -1) {
        current.add(episode);
      } else {
        current[index] = episode;
      }
    }
    _episodesByItem[itemId] = _sorted(current);
    _notify();
  }

  List<Episode> _sorted(List<Episode> episodes) {
    final sorted = List<Episode>.of(episodes)
      ..sort((a, b) {
        final bySeason = a.seasonNumber.compareTo(b.seasonNumber);
        if (bySeason != 0) return bySeason;
        return a.episodeNumber.compareTo(b.episodeNumber);
      });
    return sorted;
  }

  /// Counts the watched episodes of [episodes] and persists [seriesDerivedFields]
  /// on [item] — the write is skipped when nothing would change.
  Future<void> _persistDerived(MediaItem item, List<Episode> episodes) async {
    final id = _requireId(item);
    final watched = episodes.where((episode) => episode.watched).length;
    final fields = seriesDerivedFields(
      item,
      watchedCount: watched,
      totalCount: episodes.length,
      now: _clock(),
    );
    if (!_hasTrackingChange(item, fields)) return;
    final updated = await _repository.updateTracking(id, fields);
    _replace(updated);
  }

  /// Like [_persistDerived] but swallows a write failure — used while loading,
  /// where a stale derived row must not keep the episodes from showing.
  Future<void> _persistDerivedSafely(
    MediaItem item,
    List<Episode> episodes,
  ) async {
    try {
      await _persistDerived(item, episodes);
    } on MediaRepositoryException {
      // Non-fatal: the episodes are shown, the derived row is recomputed on
      // the next change.
    }
  }

  /// `true` when [fields] would actually change [item] (so a no-op write — and
  /// its `updated_at` bump — is avoided when a series detail view is reopened).
  bool _hasTrackingChange(MediaItem item, Map<String, dynamic> fields) {
    for (final entry in fields.entries) {
      switch (entry.key) {
        case 'progress_percent':
          final next = entry.value;
          final current = item.progressPercent;
          if (next is num) {
            if (current == null || (current - next).abs() > 0.0001) return true;
          } else if (current != null) {
            return true;
          }
        case 'status':
          if (entry.value != item.status.wire) return true;
        case 'started_at':
          if (entry.value != null && item.startedAt == null) return true;
        case 'completed_at':
          if (entry.value != null && item.completedAt == null) return true;
      }
    }
    return false;
  }

  /// Re-fetches the stored episode metadata of a series in [language],
  /// preserving `watched` / `watched_at`.
  ///
  /// Called by the language-driven metadata refresh. A failing season request
  /// is skipped — it never aborts the run and never fails the media item.
  Future<void> _refreshSeriesEpisodes(
    MediaItem item,
    AppLanguage language,
  ) async {
    final id = item.id;
    final tmdbId = int.tryParse(item.externalId ?? '');
    if (id == null || tmdbId == null) return;

    List<Episode> stored;
    try {
      stored = await _repository.fetchEpisodes(id);
    } catch (_) {
      return;
    }
    if (stored.isEmpty) return; // lazy load fills a series with no episodes

    final previous = <String, Episode>{
      for (final episode in stored)
        '${episode.seasonNumber}:${episode.episodeNumber}': episode,
    };
    final seasonNumbers = <int>{
      for (final episode in stored) episode.seasonNumber,
    }.toList()..sort();

    final refreshed = <Episode>[];
    for (final seasonNumber in seasonNumbers) {
      try {
        final season = await _tmdbClient.fetchSeason(
          tmdbId,
          seasonNumber,
          language: language.tmdbCode,
        );
        for (final episode in season.episodes) {
          refreshed.add(
            _episodeFromTmdb(
              id,
              seasonNumber,
              episode,
              previous: previous['$seasonNumber:${episode.episodeNumber}'],
            ),
          );
        }
      } catch (_) {
        // One season failed: keep its stored rows, keep going.
        continue;
      }
    }
    if (refreshed.isEmpty) return;

    try {
      final saved = await _repository.upsertEpisodeMetadata(refreshed);
      if (_episodesByItem.containsKey(id)) {
        _mergeEpisodes(id, saved.isEmpty ? refreshed : saved);
      }
    } catch (_) {
      // Keep the stored episode snapshot; the run continues.
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // metadata refresh
  // ───────────────────────────────────────────────────────────────────────────

  /// `true` while a refresh run is in flight (drives the progress banner).
  bool get refreshingMetadata => _refreshingMetadata;

  /// Items already handled in the current run.
  int get metadataRefreshDone => _metadataRefreshDone;

  /// Candidates of the current run.
  int get metadataRefreshTotal => _metadataRefreshTotal;

  /// The language the current run loads metadata in.
  AppLanguage? get metadataRefreshLanguage => _metadataRefreshLanguage;

  /// Result of the most recent completed run (including empty ones).
  MetadataRefreshResult? get lastMetadataRefresh => _lastMetadataRefresh;

  /// Increments once per completed run — the UI uses this to show the result
  /// snack bar exactly once per run (also for the automatic one).
  int get metadataRefreshRuns => _metadataRefreshRuns;

  /// Re-loads the metadata of every stored TMDB item in [language] and stores
  /// it, so the library shows localized titles/overviews.
  ///
  /// Robust by design: a failing request (or write) only skips *that* item —
  /// its stored snapshot stays visible — and the run reports
  /// `updated`/`total`. Concurrent calls share the in-flight run.
  Future<MetadataRefreshResult> refreshMetadata({
    required AppLanguage language,
  }) {
    final active = _activeRefresh;
    if (active != null) return active;

    final future = _runMetadataRefresh(language);
    _activeRefresh = future.whenComplete(() => _activeRefresh = null);
    return _activeRefresh!;
  }

  Future<MetadataRefreshResult> _runMetadataRefresh(
    AppLanguage language,
  ) async {
    final targets = _items.where(_isTmdbItem).toList(growable: false);
    if (targets.isEmpty) {
      _lastMetadataRefresh = MetadataRefreshResult.empty;
      return MetadataRefreshResult.empty;
    }

    _refreshingMetadata = true;
    _metadataRefreshDone = 0;
    _metadataRefreshTotal = targets.length;
    _metadataRefreshLanguage = language;
    _notify();

    var updated = 0;
    var next = 0;
    final workerCount = _maxConcurrency < targets.length
        ? _maxConcurrency
        : targets.length;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= targets.length) return;
        if (await _refreshItem(targets[index], language)) updated++;
        _metadataRefreshDone++;
        _notify();
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < workerCount; i++) worker(),
    ]);

    final result = MetadataRefreshResult(
      updated: updated,
      total: targets.length,
      failed: targets.length - updated,
    );
    _lastMetadataRefresh = result;
    _metadataRefreshRuns++;
    _refreshingMetadata = false;
    _metadataRefreshLanguage = null;
    _notify();

    // Show the freshly stored titles right away.
    if (updated > 0) await load();

    return result;
  }

  /// Re-fetches one item. Returns `false` when it could not be refreshed —
  /// the stored snapshot then stays untouched.
  Future<bool> _refreshItem(MediaItem item, AppLanguage language) async {
    final tmdbId = int.tryParse(item.externalId ?? '');
    if (tmdbId == null) return false;

    final type = item.kind == MediaKind.series
        ? TmdbMediaType.tv
        : TmdbMediaType.movie;

    try {
      final details = await _tmdbClient.fetchDetails(
        TmdbSearchResult(id: tmdbId, type: type, title: item.title),
        language: language.tmdbCode,
      );
      final title = details.title.trim();
      if (title.isEmpty) return false;

      final isSeries = details is TmdbTvDetails;
      // `runtime` is a movie-only metadata field (series runtimes live on the
      // episodes) — refreshed together with the rest of the snapshot.
      final runtime = details is TmdbMovieDetails
          ? details.runtime
          : item.runtime;
      await _repository.updateMetadata(
        item.copyWith(
          title: title,
          originalTitle: _nonEmpty(details.originalTitle),
          releaseYear: details.year,
          overview: _nonEmpty(details.overview),
          posterUrl: details.posterUrl,
          totalSeasons: isSeries ? details.numberOfSeasons : item.totalSeasons,
          totalEpisodes: isSeries
              ? details.numberOfEpisodes
              : item.totalEpisodes,
          runtime: runtime,
        ),
      );
      // A series also carries localized episode metadata — refresh it in the
      // same language. Failures here never fail the item (see the method).
      if (isSeries) {
        await _refreshSeriesEpisodes(item, language);
      }
      return true;
    } catch (_) {
      // Single-item failure: keep the old data, keep going.
      return false;
    }
  }

  /// A refresh candidate is always a TMDB item.
  ///
  /// Books (`external_source == 'openlibrary'`) are deliberately **excluded**:
  /// OpenLibrary is not a localized metadata API — a work's title does not
  /// vary by language (only its editions do, and the stored snapshot already
  /// holds the fields we show). Re-fetching would add requests without
  /// improving anything, and books must not inflate `total`/`failed`.
  bool _isTmdbItem(MediaItem item) =>
      item.externalSource == tmdbSource &&
      item.externalId != null &&
      item.externalId!.isNotEmpty;

  /// An empty TMDB field means "no value in this language" — treated as
  /// `null` so [MediaItem.copyWith] keeps the value already stored.
  String? _nonEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // language trigger
  // ───────────────────────────────────────────────────────────────────────────

  void _onSettingsChanged() {
    final language = _settings.language;
    if (language == _language) return;
    _language = language;
    // Fire and forget: the library stays usable while this runs.
    refreshMetadata(language: language);
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
